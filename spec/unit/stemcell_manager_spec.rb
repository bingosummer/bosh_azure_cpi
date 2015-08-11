require 'spec_helper'

describe Bosh::AzureCloud::StemcellManager do
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:stemcell_manager) { Bosh::AzureCloud::StemcellManager.new(blob_manager) }

  describe "#create_stemcell" do
    context "the container exists" do
      before do
        allow(blob_manager).to receive(:container_exist?).
          and_return(true)
        allow(Open3).to receive(:capture2e).and_return(["",
          double("status", :exitstatus => 0)])
      end
      it "does not create the container and create the stemcell" do
        expect(blob_manager).not_to receive(:create_container)
        expect(blob_manager).to receive(:create_page_blob)

        expect(stemcell_manager.create_stemcell("",{})).not_to be_empty
      end
    end

    context "the container does not exist and create the stemcell" do
      before do
        allow(blob_manager).to receive(:container_exist?).
          and_return(false)
        allow(Open3).to receive(:capture2e).and_return(["",
          double("status", :exitstatus => 0)])
      end
      it "creates the container" do
        expect(blob_manager).to receive(:create_container)
        expect(blob_manager).to receive(:create_page_blob)

        expect(stemcell_manager.create_stemcell("",{})).not_to be_empty
      end
    end
  end  

  describe "#delete_stemcell" do
    context "the stemcell exists" do
      before do
        allow(blob_manager).to receive(:blob_exist?).
          and_return(true)
      end
      it "deletes the stemcell" do
        expect(blob_manager).to receive(:delete_blob)

        stemcell_manager.delete_stemcell("foo")
      end
    end

    context "the stemcell does not exist" do
      before do
        allow(blob_manager).to receive(:blob_exist?).
          and_return(false)
      end
      it "does not delete the stemcell" do
        expect(blob_manager).not_to receive(:delete_blob)

        stemcell_manager.delete_stemcell("foo")
      end
    end
  end  
end
