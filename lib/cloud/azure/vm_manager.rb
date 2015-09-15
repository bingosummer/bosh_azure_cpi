module Bosh::AzureCloud
  class VMManager
    include Helpers

    AZURE_TAGS = {'user-agent' => 'bosh'}

    def initialize(azure_properties, registry_endpoint, disk_manager, azure_client2)
      @azure_properties = azure_properties
      @registry_endpoint = registry_endpoint
      @disk_manager = disk_manager
      @azure_client2 = azure_client2

      @logger = Bosh::Clouds::Config.logger
    end

    def create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
      instance_is_created = false
      subnet = @azure_client2.get_network_subnet_by_name(network_configurator.virtual_network_name, network_configurator.subnet_name)
      raise "Cannot find the subnet #{network_configurator.virtual_network_name}/#{network_configurator.subnet_name}" if subnet.nil?

      caching = 'ReadWrite'
      if resource_pool.has_key?('caching')
        caching = resource_pool['caching']
        validate_disk_caching(caching)
      end

      instance_id  = generate_instance_id(storage_account_name, uuid)

      load_balancer = nil
      is_internal_load_balancer = false
      unless network_configurator.vip_network.nil?
        public_ip = @azure_client2.list_public_ips().find { |ip| ip[:ip_address] == network_configurator.public_ip}
        cloud_error("Cannot find the public IP address #{network_configurator.public_ip}") if public_ip.nil?
        @azure_client2.create_load_balancer(instance_id, public_ip, AZURE_TAGS,
                                      network_configurator.tcp_endpoints,
                                      network_configurator.udp_endpoints)
        load_balancer = @azure_client2.get_load_balancer_by_name(instance_id)
      end
      if resource_pool.has_key?('load_balancer')
        cloud_error("Cannot bind two load balancers to one VM") unless load_balancer.nil?
        is_internal_load_balancer = true
        load_balancer = @azure_client2.get_load_balancer_by_name(resource_pool['load_balancer'])
        cloud_error("Cannot find the load balancer #{resource_pool['load_balancer']}") if load_balancer.nil?
      end

      storage_account = @azure_client2.get_storage_account_by_name(storage_account_name)
      nic_params = {
        :name                => instance_id,
        :location            => storage_account[:location],
        :private_ip          => network_configurator.private_ip,
      }
      network_tags = AZURE_TAGS
      if resource_pool.has_key?('availability_set')
        network_tags = network_tags.merge({'availability_set' => resource_pool['availability_set']})
      end
      @azure_client2.create_network_interface(nic_params, subnet, network_tags, load_balancer)
      network_interface = @azure_client2.get_network_interface_by_name(instance_id)

      availability_set = nil
      if resource_pool.has_key?('availability_set')
        availability_set = @azure_client2.get_availability_set_by_name(resource_pool['availability_set'])
        if availability_set.nil?
          avset_params = {
            :name                         => resource_pool['availability_set'],
            :location                     => storage_account[:location],
            :tags                         => AZURE_TAGS,
            :platform_update_domain_count => resource_pool['platform_update_domain_count'] || 5,
            :platform_fault_domain_count  => resource_pool['platform_fault_domain_count'] || 3
          }
          @azure_client2.create_availability_set(avset_params)
          availability_set = @azure_client2.get_availability_set_by_name(resource_pool['availability_set'])
        end
      end

      os_disk_name = @disk_manager.generate_os_disk_name(instance_id)
      vm_params = {
        :name                => instance_id,
        :location            => storage_account[:location],
        :tags                => AZURE_TAGS,
        :vm_size             => resource_pool['instance_type'],
        :username            => @azure_properties['ssh_user'],
        :custom_data         => get_user_data(instance_id, network_configurator.dns),
        :image_uri           => stemcell_uri,
        :os_disk_name        => os_disk_name,
        :os_vhd_uri          => @disk_manager.get_disk_uri(os_disk_name),
        :caching             => caching,
        :ssh_cert_data       => @azure_properties['ssh_certificate']
      }
      instance_is_created = true
      @azure_client2.create_virtual_machine(vm_params, network_interface, availability_set)

      instance_id
    rescue => e
      @azure_client2.delete_virtual_machine(instance_id) if instance_is_created
      delete_availability_set(availability_set[:name]) unless availability_set.nil?
      @azure_client2.delete_network_interface(network_interface[:name]) unless network_interface.nil?
      @azure_client2.delete_load_balancer(load_balancer[:name]) unless load_balancer.nil? || is_internal_load_balancer
      raise Bosh::Clouds::VMCreationFailed.new(false), "#{e.message}\n#{e.backtrace.join("\n")}"
    end

    def find(instance_id)
      @azure_client2.get_virtual_machine_by_name(instance_id)
    end

    def delete(instance_id)
      @logger.info("delete(#{instance_id})")

      vm = @azure_client2.get_virtual_machine_by_name(instance_id)
      @azure_client2.delete_virtual_machine(instance_id) unless vm.nil?

      load_balancer = @azure_client2.get_load_balancer_by_name(instance_id)
      @azure_client2.delete_load_balancer(instance_id) unless load_balancer.nil?

      network_interface = @azure_client2.get_network_interface_by_name(instance_id)
      unless network_interface.nil?
        if network_interface[:tags].has_key?('availability_set')
          delete_availability_set(network_interface[:tags]['availability_set'])
        end

        @azure_client2.delete_network_interface(instance_id)
      end

      os_disk_name = @disk_manager.generate_os_disk_name(instance_id)
      @disk_manager.delete_disk(os_disk_name) if @disk_manager.has_disk?(os_disk_name)

      # Cleanup invalid VM status file
      storage_account_name = get_storage_account_name_from_instance_id(instance_id)
      @disk_manager.delete_vm_status_files(storage_account_name, instance_id)
    end

    def reboot(instance_id)
      @logger.info("reboot(#{instance_id})")
      @azure_client2.restart_virtual_machine(instance_id)
    end

    def set_metadata(instance_id, metadata)
      @logger.info("set_metadata(#{instance_id}, #{metadata})")
      @azure_client2.update_tags_of_virtual_machine(instance_id, metadata.merge(AZURE_TAGS))
    end

    ##
    # Attach a disk to the Vm
    #
    # @param [String] instance_id Instance id
    # @param [String] disk_name disk name
    # @return [String] volume name. "/dev/sd[c-r]"
    def attach_disk(instance_id, disk_name)
      @logger.info("attach_disk(#{instance_id}, #{disk_name})")
      disk_uri = @disk_manager.get_disk_uri(disk_name)
      caching = @disk_manager.get_data_disk_caching(disk_name)
      disk = @azure_client2.attach_disk_to_virtual_machine(instance_id, disk_name, disk_uri, caching)
      "/dev/sd#{('c'.ord + disk[:lun]).chr}"
    end

    def detach_disk(instance_id, disk_name)
      @logger.info("detach_disk(#{instance_id}, #{disk_name})")
      @azure_client2.detach_disk_from_virtual_machine(instance_id, disk_name)
    end

    private

    def get_user_data(vm_name, dns)
      user_data = {registry: {endpoint: @registry_endpoint}}
      user_data[:server] = {name: vm_name}
      user_data[:dns] = {nameserver: dns} if dns
      Base64.strict_encode64(Yajl::Encoder.encode(user_data))
    end

    def delete_availability_set(name)
      availability_set = @azure_client2.get_availability_set_by_name(name)
      if !availability_set.nil? && availability_set[:virtual_machines].size == 0
        @azure_client2.delete_availability_set(name)
      end
    end
  end
end
