require 'spec_helper'

describe Bosh::AzureCloud::VMManager do
  let(:azure_properties) { mock_cloud_options['properties'].fetch('azure') }
  let(:registry_endpoint) { mock_registry.endpoint }
  let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager) }
  let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_properties, registry_endpoint, disk_manager) }
  let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:storage_account) {
    {
      :id => "foo",
      :name => azure_properties['storage_account_name'],
      :location => "bar",
      :provisioning_state => "bar",
      :account_type => "foo",
      :primary_endpoints => "bar"
    }
  }
  let(:load_balancer) {
    {
      :name => "foo",
    }
  }
  let(:network_interface) {
    {
      :name => "foo",
    }
  }
  let(:instance_id) { double("fake-instance-id") }

  before do
    allow(Bosh::AzureCloud::AzureClient2).to receive(:new).
      and_return(client2)
    allow(client2).to receive(:get_storage_account_by_name).
      with(azure_properties['storage_account_name']).
      and_return(storage_account)
  end

  describe "#create" do
    let(:uuid) { double("uuid") }
    let(:stemcell_uri) { double("stemcell_uri") }
    let(:network_configurator) { instance_double(Bosh::AzureCloud::NetworkConfigurator) }
    let(:resource_pool) {
      {
        'instance_type' => 'foo'
      }
    }
    let(:subnet) { double("subnet") }
    let(:public_ips) {
      [
        {
          :ip_address => "reserved-ip"
        },
        {
          :ip_address => "not-reserved-ip"
        }
      ]
    }

    before do
      allow(network_configurator).to receive(:virtual_network_name).
        and_return("fake-virtual-network-name")
      allow(network_configurator).to receive(:subnet_name).
        and_return("fake-subnet-name")
      allow(client2).to receive(:get_network_subnet_by_name).
        and_return(subnet)
      allow(network_configurator).to receive(:vip_network).
        and_return("fake-vip-network")
      allow(client2).to receive(:list_public_ips).
        and_return(public_ips)
      allow(network_configurator).to receive(:reserved_ip).
        and_return("reserved-ip")
      allow(network_configurator).to receive(:tcp_endpoints).
        and_return("fake-tcp-endpoints")
      allow(network_configurator).to receive(:udp_endpoints).
        and_return("fake-udp-endpoints")
      allow(client2).to receive(:create_load_balancer)
      allow(client2).to receive(:get_load_balancer_by_name).
        with(uuid).and_return(load_balancer)
      allow(network_configurator).to receive(:private_ip).
        and_return("fake-private-ip")
      allow(client2).to receive(:create_network_interface)
      allow(client2).to receive(:get_network_interface_by_name).
        with(uuid).and_return(network_interface)
      allow(disk_manager).to receive(:create_container)
      allow(network_configurator).to receive(:dns).
        and_return("fake-dns")
      allow(disk_manager).to receive(:get_disk_uri).and_return("fake-disk-uri")
      allow(client2).to receive(:create_virtual_machine)
    end

    context "when subnet is not found" do
      it "raise an error" do
        allow(client2).to receive(:get_network_subnet_by_name).
          and_return(nil)
        expect {
          vm_manager.create(uuid, stemcell_uri, azure_properties, network_configurator, resource_pool)
        }.to raise_error /Cannot find the subnet/
      end
    end

    context "when public ip is not found" do
      it "raises an error" do
        allow(client2).to receive(:list_public_ips).
          and_return([])
        expect(client2).not_to receive(:delete_virtual_machine)
        expect(client2).not_to receive(:delete_network_interface)
        expect(client2).not_to receive(:delete_load_balancer)
        expect {
          vm_manager.create(uuid, stemcell_uri, azure_properties, network_configurator, resource_pool)
        }.to raise_error /Cannot find the reserved IP address/
      end
    end

    context "when load balancer is not created" do
      it "raises an error" do
        allow(client2).to receive(:create_load_balancer).
          and_raise("load balancer is not created")
        expect(client2).not_to receive(:delete_virtual_machine)
        expect(client2).not_to receive(:delete_network_interface)
        expect(client2).not_to receive(:delete_load_balancer)
        expect {
          vm_manager.create(uuid, stemcell_uri, azure_properties, network_configurator, resource_pool)
        }.to raise_error /load balancer is not created/
      end
    end

    context "when network interface is not created" do
      it "raises an error" do
        allow(client2).to receive(:create_network_interface).
          and_raise("network interface is not created")
        expect(client2).not_to receive(:delete_virtual_machine)
        expect(client2).not_to receive(:delete_network_interface)
        expect(client2).to receive(:delete_load_balancer)
        expect {
          vm_manager.create(uuid, stemcell_uri, azure_properties, network_configurator, resource_pool)
        }.to raise_error /network interface is not created/
      end
    end

    context "when virtual machine is not created" do
      it "raises an error" do
        allow(client2).to receive(:create_virtual_machine).
          and_raise("virtual machine is not created")
        expect(client2).to receive(:delete_virtual_machine)
        expect(client2).to receive(:delete_network_interface)
        expect(client2).to receive(:delete_load_balancer)
        expect {
          vm_manager.create(uuid, stemcell_uri, azure_properties, network_configurator, resource_pool)
        }.to raise_error /virtual machine is not created/
      end
    end

    context "when everything is fine" do
      it "creates a vm without any error" do
        expect(
          vm_manager.create(
            uuid,
            stemcell_uri,
            azure_properties,
            network_configurator,
            resource_pool)
        ).to eq(uuid)
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
    let(:network_interface) { double("network_interface") }
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

      os_disk = "bosh-os-#{instance_id}"
      allow(disk_manager).to receive(:has_disk?).
        with(os_disk).and_return(true)
      expect(disk_manager).to receive(:delete_disk).with(os_disk)

      expect(disk_manager).to receive(:delete_vm_status_files).
        with(instance_id)

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
      expect(client2).to receive(:update_tags_of_virtual_machine).with(instance_id, {})
      vm_manager.set_metadata(instance_id, {})
    end
  end  

  describe "#attach_disk" do
    let(:disk_name) { "fake-disk-name" }
    let(:disk_uri) { "fake-disk-uri" }
    let(:disk) { {:lun => 0} }
    it "attaches the disk to an instance" do
      allow(disk_manager).to receive(:get_disk_uri).
        with(disk_name).and_return(disk_uri)
      expect(client2).to receive(:attach_disk_to_virtual_machine).
        with(instance_id, disk_name, disk_uri).
        and_return(disk)
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
