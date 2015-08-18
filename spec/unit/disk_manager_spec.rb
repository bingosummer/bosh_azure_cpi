require 'spec_helper'

describe Bosh::AzureCloud::DiskManager do
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:disk_manager) { Bosh::AzureCloud::DiskManager.new(blob_manager) }

  let(:disk_name) { "fake-disk-123" }

  describe "#delete_disk" do
    context "the disk exists" do
      before do
        allow(blob_manager).to receive(:blob_exist?).
          and_return(true)
      end
      it "deletes the disk" do
        expect(blob_manager).to receive(:delete_blob)

        disk_manager.delete_disk(disk_name)
      end
    end

    context "the disk does not exist" do
      before do
        allow(blob_manager).to receive(:blob_exist?).
          and_return(false)
      end
      it "does not delete the disk" do
        expect(blob_manager).not_to receive(:delete_blob)

        disk_manager.delete_disk(disk_name)
      end
    end
  end  

  describe "#delete_vm_status_files" do
    it "deletes vm status files" do
      allow(blob_manager).to receive(:list_blobs).
          and_return([
            double("blob", :name => "a.status"),
            double("blob", :name => "b.status"),
            double("blob", :name => "a.vhd"),
            double("blob", :name => "b.vhd")
          ])
      expect(blob_manager).to receive(:delete_blob).with("bosh", "a.status")
      expect(blob_manager).to receive(:delete_blob).with("bosh", "b.status")

      disk_manager.delete_vm_status_files("")
    end
  end  

  describe "#snapshot_disk" do
    it "returns the snapshot disk name" do
      expect(blob_manager).to receive(:snapshot_blob)
      expect(disk_manager.snapshot_disk(disk_name, {})).not_to be_empty
    end
  end  

  describe "#create_disk" do
    it "returns the disk name" do
      size = 100
      expect(blob_manager).to receive(:create_empty_vhd_blob)
      expect(disk_manager.create_disk(size)).not_to be_empty
    end
  end  
end
