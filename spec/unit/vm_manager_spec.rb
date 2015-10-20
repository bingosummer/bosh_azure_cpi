require 'spec_helper'

describe Bosh::AzureCloud::VMManager do
  let(:azure_properties) { mock_azure_properties }
  let(:registry_endpoint) { mock_registry.endpoint }
  let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager) }
  let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_properties, registry_endpoint, disk_manager, client2) }

  let(:uuid) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
  let(:instance_id) { "#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}-#{uuid}" }
  let(:storage_account_name) { MOCK_DEFAULT_STORAGE_ACCOUNT_NAME }

  describe "#create" do
    # Parameters
    let(:stemcell_uri) { double("stemcell_uri") }
    let(:resource_pool) {
      {
        'instance_type' => 'Standard_D1',
        'storage_account_name' => 'dfe03ad623f34d42999e93ca',
        'caching' => 'ReadWrite',
        'availability_set' => 'fake-avset',
        'platform_update_domain_count' => 5,
        'platform_fault_domain_count' => 3,
        'load_balancer' => 'fake-lb-name'
      }
    }
    let(:network_configurator) { instance_double(Bosh::AzureCloud::NetworkConfigurator) }

    before do
      allow(Bosh::AzureCloud::AzureClient2).to receive(:new).
        and_return(client2)
      allow(network_configurator).to receive(:virtual_network_name).
        and_return("fake-virtual-network-name")
      allow(network_configurator).to receive(:subnet_name).
        and_return("fake-subnet-name")
    end

    context "when subnet is not found" do
      it "raise an error" do
        allow(client2).to receive(:get_network_subnet_by_name).
          and_return(nil)
        expect {
          vm_manager.create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
        }.to raise_error /Cannot find the subnet/
      end
    end

    context "when caching is invalid" do
      let(:subnet) { double("subnet") }
      let(:resource_pool) {
        {
          'caching' => 'InvalidCachingOption'
        }
      }

      it "raise an error" do
        allow(client2).to receive(:get_network_subnet_by_name).
          and_return(subnet)

        expect {
          vm_manager.create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
        }.to raise_error /Unknown disk caching/
      end
    end

    context "when public ip is not found" do
      let(:subnet) { double("subnet") }

      before do
        allow(client2).to receive(:get_network_subnet_by_name).
          and_return(subnet)
        allow(network_configurator).to receive(:vip_network).
          and_return("fake-vip-network")
      end
 
      context "when the public ip list azure returns is empty" do
        it "raises an error" do
          allow(client2).to receive(:list_public_ips).
            and_return([])
          allow(network_configurator).to receive(:public_ip).
            and_return("public-ip")

          expect(client2).not_to receive(:delete_virtual_machine)
          expect(client2).not_to receive(:delete_availability_set)
          expect(client2).not_to receive(:delete_network_interface)
          expect(client2).not_to receive(:delete_load_balancer)
          expect {
            vm_manager.create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
          }.to raise_error /Cannot find the public IP address/
        end
      end

      context "when the public ip list azure returns does not match the configured one" do
        let(:public_ips) {
          [
            {
              :ip_address => "public-ip"
            },
            {
              :ip_address => "not-public-ip"
            }
          ]
        }

        it "raises an error" do
          allow(client2).to receive(:get_network_subnet_by_name).
            and_return(subnet)
          allow(network_configurator).to receive(:vip_network).
            and_return("fake-vip-network")
          allow(client2).to receive(:list_public_ips).
            and_return(public_ips)
          allow(network_configurator).to receive(:public_ip).
            and_return("not-exist-public-ip")

          expect(client2).not_to receive(:delete_virtual_machine)
          expect(client2).not_to receive(:delete_availability_set)
          expect(client2).not_to receive(:delete_network_interface)
          expect(client2).not_to receive(:delete_load_balancer)
          expect {
            vm_manager.create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
          }.to raise_error /Cannot find the public IP address/
        end
      end
    end

    context "when creating load balancer failed" do
      let(:subnet) { double("subnet") }

      before do
        allow(client2).to receive(:get_network_subnet_by_name).
          and_return(subnet)
      end

      context "vip network is not null" do
        let(:public_ips) {
          [
            {
              :ip_address => "public-ip"
            }
          ]
        }

        before do
          allow(network_configurator).to receive(:vip_network).
            and_return("fake-vip-network")
          allow(client2).to receive(:list_public_ips).
            and_return(public_ips)
          allow(network_configurator).to receive(:public_ip).
            and_return("public-ip")
          allow(network_configurator).to receive(:tcp_endpoints).
            and_return([])
          allow(network_configurator).to receive(:udp_endpoints).
            and_return([])
        end

        context "when public load balancer is not created" do
          it "raises an error" do
            allow(client2).to receive(:create_load_balancer).
              and_raise("load balancer is not created")

            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_availability_set)
            expect(client2).not_to receive(:delete_network_interface)
            expect(client2).not_to receive(:delete_load_balancer)

            expect {
              vm_manager.create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
            }.to raise_error /load balancer is not created/
          end
        end

        context "when binding two load balancers to one VM" do
          let(:subnet) { double("subnet") }
          let(:resource_pool) {
            {
              'load_balancer' => 'internal-lb-name'
            }
          }
          let(:load_balancer) {
            {
              :name => "internal-lb-name"
            }
          }

          it "raises an error" do
            allow(client2).to receive(:create_load_balancer)
            allow(client2).to receive(:get_load_balancer_by_name).
              and_return(load_balancer)

            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_availability_set)
            expect(client2).not_to receive(:delete_network_interface)
            expect(client2).to receive(:delete_load_balancer).
              with(load_balancer[:name])

            expect {
              vm_manager.create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
            }.to raise_error /Cannot bind two load balancers to one VM/
          end
        end
      end

      context "vip network is null" do
        context "when internal load balancer can't be found" do
          let(:resource_pool) {
            {
              'load_balancer' => 'internal-lb-name'
            }
          }

          it "raises an error" do
            allow(network_configurator).to receive(:vip_network).
              and_return(nil)
            allow(client2).to receive(:get_load_balancer_by_name).
              with(resource_pool['load_balancer']).
              and_return(nil)

            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_availability_set)
            expect(client2).not_to receive(:delete_network_interface)
            expect(client2).not_to receive(:delete_load_balancer)

            expect {
              vm_manager.create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
            }.to raise_error /Cannot find the load balancer/
          end
        end
      end
    end

    context "when network interface is not created" do
      let(:subnet) { double("subnet") }
      let(:resource_pool) {
        {
          'load_balancer' => 'internal-lb-name'
        }
      }
      let(:load_balancer) {
        {
          :name => "internal-lb-name"
        }
      }
      let(:storage_account) {
        {
          :id => "foo",
          :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
          :location => "bar",
          :provisioning_state => "bar",
          :account_type => "foo",
          :primary_endpoints => "bar"
        }
      }

      before do
        allow(client2).to receive(:get_network_subnet_by_name).
          and_return(subnet)

        allow(network_configurator).to receive(:vip_network).
          and_return(nil)
        allow(client2).to receive(:get_load_balancer_by_name).
          with(resource_pool['load_balancer']).
          and_return(load_balancer)
        allow(client2).to receive(:get_storage_account_by_name).
          with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).
          and_return(storage_account)
        allow(network_configurator).to receive(:private_ip).
          and_return('10.0.0.100')
      end

      it "raises an error" do
        allow(client2).to receive(:create_network_interface).
          and_raise("network interface is not created")

        expect(client2).not_to receive(:delete_virtual_machine)
        expect(client2).not_to receive(:delete_availability_set)
        expect(client2).not_to receive(:delete_network_interface)
        expect(client2).not_to receive(:delete_load_balancer)

        expect {
          vm_manager.create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
        }.to raise_error /network interface is not created/
      end
    end

    context "when availability set is not created" do
      let(:subnet) { double("subnet") }
      let(:resource_pool) {
        {
          'load_balancer' => 'internal-lb-name',
          'availability_set' => 'fake-avset'
        }
      }
      let(:load_balancer) {
        {
          :name => "internal-lb-name"
        }
      }
      let(:storage_account) {
        {
          :id => "foo",
          :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
          :location => "bar",
          :provisioning_state => "bar",
          :account_type => "foo",
          :primary_endpoints => "bar"
        }
      }
      let(:network_interface) {
        {
          :name => "foo"
        }
      }

      before do
        allow(client2).to receive(:get_network_subnet_by_name).
          and_return(subnet)

        allow(network_configurator).to receive(:vip_network).
          and_return(nil)
        allow(client2).to receive(:get_load_balancer_by_name).
          with(resource_pool['load_balancer']).
          and_return(load_balancer)
        allow(client2).to receive(:get_storage_account_by_name).
          with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).
          and_return(storage_account)
        allow(network_configurator).to receive(:private_ip).
          and_return('10.0.0.100')
        allow(client2).to receive(:create_network_interface)
        allow(client2).to receive(:get_network_interface_by_name).
          and_return(network_interface)
        allow(client2).to receive(:get_availability_set_by_name).
          with(resource_pool['availability_set']).
          and_return(nil)
      end

      it "raises an error" do
        allow(client2).to receive(:create_availability_set).
          and_raise("availability set is not created")

        expect(client2).not_to receive(:delete_virtual_machine)
        expect(client2).not_to receive(:delete_availability_set)
        expect(client2).to receive(:delete_network_interface)
        expect(client2).not_to receive(:delete_load_balancer)

        expect {
          vm_manager.create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
        }.to raise_error /availability set is not created/
      end
    end

    context "when creating virtual machine" do
      let(:subnet) { double("subnet") }
      let(:load_balancer) {
        {
          :name => "internal-lb-name"
        }
      }
      let(:storage_account) {
        {
          :id => "foo",
          :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
          :location => "bar",
          :provisioning_state => "bar",
          :account_type => "foo",
          :primary_endpoints => "bar"
        }
      }
      let(:network_interface) {
        {
          :name => "foo"
        }
      }
      let(:vms) { double("vms", :size => 0) }
      let(:availability_set) {
        {
          :name => "fake-avset",
          :virtual_machines => vms
        }
      }

      before do
        allow(client2).to receive(:get_network_subnet_by_name).
          and_return(subnet)

        allow(network_configurator).to receive(:vip_network).
          and_return(nil)
        allow(client2).to receive(:get_load_balancer_by_name).
          with(resource_pool['load_balancer']).
          and_return(load_balancer)
        allow(client2).to receive(:get_storage_account_by_name).
          with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).
          and_return(storage_account)
        allow(network_configurator).to receive(:private_ip).
          and_return('10.0.0.100')
        allow(client2).to receive(:create_network_interface)
        allow(client2).to receive(:get_network_interface_by_name).
          and_return(network_interface)
        allow(client2).to receive(:get_availability_set_by_name).
          with(resource_pool['availability_set']).
          and_return(availability_set)
        allow(disk_manager).to receive(:generate_os_disk_name).
          and_return("fake-os-disk-name")
        allow(network_configurator).to receive(:dns).
          and_return("fake-dns")
        allow(disk_manager).to receive(:get_disk_uri).
          and_return("fake-disk-uri")
      end

      context "when VM is not created" do
        it "raises an error" do
          allow(client2).to receive(:create_virtual_machine).
            and_raise("virtual machine is not created")

          expect(client2).to receive(:delete_virtual_machine)
          expect(client2).to receive(:delete_availability_set)
          expect(client2).to receive(:delete_network_interface)
          expect(client2).not_to receive(:delete_load_balancer)

          expect {
            vm_manager.create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
          }.to raise_error /virtual machine is not created/
        end
      end

      context "when VM is created" do
        it "does not raise an error" do
          allow(client2).to receive(:create_virtual_machine)

          expect(client2).not_to receive(:delete_virtual_machine)
          expect(client2).not_to receive(:delete_availability_set)
          expect(client2).not_to receive(:delete_network_interface)
          expect(client2).not_to receive(:delete_load_balancer)

          vm_manager.create(uuid, storage_account_name, stemcell_uri, resource_pool, network_configurator)
        end
      end
    end
  end  

  describe "#find" do
    it "finds the instance by id" do
      expect(client2).to receive(:get_virtual_machine_by_name).with(instance_id)
      vm_manager.find(instance_id)
    end
  end  

  describe "#delete" do
    let(:vm) { double("vm") }
    let(:load_balancer) { double("load_balancer") }
    let(:network_interface) {
      {
        :tags => {}
      }
    }
    it "deletes the instance by id" do
      allow(client2).to receive(:get_virtual_machine_by_name).
        with(instance_id).and_return(vm)
      expect(client2).to receive(:delete_virtual_machine).with(instance_id)

      allow(client2).to receive(:get_load_balancer_by_name).
        with(instance_id).and_return(load_balancer)
      expect(client2).to receive(:delete_load_balancer).with(instance_id)

      allow(client2).to receive(:get_network_interface_by_name).
        with(instance_id).and_return(network_interface)
      expect(client2).to receive(:delete_network_interface).with(instance_id)

      os_disk_name = "fake-os-disk-name"
      allow(disk_manager).to receive(:generate_os_disk_name).
        and_return(os_disk_name)
      expect(disk_manager).to receive(:has_disk?).
        with(os_disk_name).
        and_return(true)
      expect(disk_manager).to receive(:delete_disk).with(os_disk_name)

      expect(disk_manager).to receive(:delete_vm_status_files).
        with(storage_account_name, instance_id)

      vm_manager.delete(instance_id)
    end
  end  

  describe "#reboot" do
    it "reboots the instance by id" do
      expect(client2).to receive(:restart_virtual_machine).with(instance_id)
      vm_manager.reboot(instance_id)
    end
  end  

  describe "#set_metadata" do
    it "sets the metadata of the instance by id" do
      expect(client2).to receive(:update_tags_of_virtual_machine).
        with(instance_id, {'user-agent' => 'bosh'})
      vm_manager.set_metadata(instance_id, {})
    end
  end  

  describe "#attach_disk" do
    let(:disk_name) { "fake-disk-name-None" }
    let(:disk_uri) { "fake-disk-uri" }
    let(:cache) { "None" }
    let(:disk) { {:lun => 0} }
    it "attaches the disk to an instance" do
      allow(disk_manager).to receive(:get_disk_uri).
        with(disk_name).and_return(disk_uri)
      expect(client2).to receive(:attach_disk_to_virtual_machine).
        with(instance_id, disk_name, disk_uri, cache).
        and_return(disk)
      expect(disk_manager).to receive(:get_data_disk_caching).
        with(disk_name).
        and_return(cache)
      expect(vm_manager.attach_disk(instance_id, disk_name)).to eq("/dev/sdc")
    end
  end  

  describe "#detach_disk" do
    let(:disk_name) { "fake-disk-name" }
    it "detaches the disk from an instance" do
      expect(client2).to receive(:detach_disk_from_virtual_machine).
        with(instance_id, disk_name)
      vm_manager.detach_disk(instance_id, disk_name)
    end
  end  
end
