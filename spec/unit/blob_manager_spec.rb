require 'spec_helper'

describe Bosh::AzureCloud::BlobManager do
  let(:blob_manager) { Bosh::AzureCloud::BlobManager.new }
  let(:blob_service_client) { instance_double("Azure::BlobService") }

  let(:container_name) { "fake-container-123" }
  let(:blob_name) { "fake-blob-123" }

  before do
    allow(Azure::BlobService).to receive(:new).and_return(blob_service_client)
  end

  describe "#delete_blob" do
    it "delete the blob" do
      expect(blob_service_client).to receive(:delete_blob).
        with(container_name, blob_name, {:delete_snapshots => :include})

      blob_manager.delete_blob(container_name, blob_name)
    end
  end  

  describe "#get_blob_uri" do
    host = "http://fake-storage-blob-host"
    it "gets the uri of the blob" do
      Azure.config.storage_blob_host = host
      expect(blob_manager.get_blob_uri(container_name, blob_name)).to eq("#{host}/#{container_name}/#{blob_name}")
    end
  end  

  describe "#delete_blob_snapshot" do
    it "delete the blob snapshot" do
      snapshot_time = 10
      expect(blob_service_client).to receive(:delete_blob).
        with(container_name, blob_name, {:snapshot => snapshot_time})

      blob_manager.delete_blob_snapshot(container_name, blob_name, snapshot_time)
    end
  end  

  describe "#create_page_blob" do
    file_path = "/tmp/fake_image"
    File.open(file_path, 'wb') { |f| f.write("Hello CloudFoundry!") }
    context "when upload page blob succeeds" do
      before do
        allow(blob_service_client).to receive(:create_page_blob)
        allow(blob_service_client).to receive(:create_blob_pages)
      end
      it "raise no error" do
        expect {
          blob_manager.create_page_blob(container_name, file_path, blob_name)        
        }.not_to raise_error
      end
    end
    context "when upload page blob fails" do
      before do
        allow(blob_service_client).to receive(:create_page_blob).and_raise(StandardError)
      end
      it "raise an error" do
        expect {
          blob_manager.create_page_blob(container_name, file_path, blob_name)        
        }.to raise_error /Failed to upload page blob/
      end
    end
  end  

  describe "#create_empty_vhd_blob" do
    context "when creating empty vhd blob succeeds" do
      before do
        allow(blob_service_client).to receive(:create_page_blob)
        allow(blob_service_client).to receive(:create_blob_pages)
      end
      it "raise no error" do
        expect {
          blob_manager.create_empty_vhd_blob(container_name, blob_name, 1)    
        }.not_to raise_error
      end
    end

    context "when creating empty vhd blob fails" do
      context "blob is not created" do
        before do
          allow(blob_service_client).to receive(:create_page_blob).and_raise(StandardError)
        end
        it "raise an error and do not delete blob" do
          expect(blob_service_client).not_to receive(:delete_blob)
          expect {
            blob_manager.create_empty_vhd_blob(container_name, blob_name, 1)
          }.to raise_error /Failed to create empty vhd blob/
        end
      end

      context "blob is created" do
        before do
          allow(blob_service_client).to receive(:create_page_blob)
          allow(blob_service_client).to receive(:create_blob_pages).and_raise(StandardError)
        end
        it "raise an error and delete blob" do
          expect(blob_service_client).to receive(:delete_blob)
          expect {
            blob_manager.create_empty_vhd_blob(container_name, blob_name, 1) 
          }.to raise_error /Failed to create empty vhd blob/
        end
      end
    end
  end  

  describe "#blob_exist?" do
    context "when the blob exists" do
      before do
        allow(blob_service_client).to receive(:get_blob_properties).
          and_return(instance_double("Azure::Blob::Blob", :name => blob_name))
      end

      it "return true" do
        expect(blob_manager.blob_exist?(container_name, blob_name)).to be(true)
      end
    end

    context "fail to get blob properties and get 404" do
      before do
        allow(blob_service_client).to receive(:get_blob_properties).and_raise("(404)")
      end
      it "return false" do
        expect(blob_manager.blob_exist?(container_name, blob_name)).to be(false)
      end
    end

    context "fail to get blob properties and get no 404" do
      before do
        allow(blob_service_client).to receive(:get_blob_properties).and_raise("Not exist")
      end
      it "raise a cloud error" do
        expect{
          blob_manager.blob_exist?(container_name, blob_name)
        }.to raise_error /blob_exist/
      end
    end
  end  

  describe "#list_blobs" do
    class MyArray < Array
      attr_accessor :continuation_token
    end

    context "when the container is empty" do
      tmp_blobs = MyArray.new
      before do
        allow(blob_service_client).to receive(:list_blobs).and_return(tmp_blobs)
      end
      it "returns empty blobs" do
        expect(blob_manager.list_blobs(container_name)).to be_empty
      end
    end

    context "when the container is not empty" do
      context "when blob service client returns no continuation_token" do
        tmp_blobs = MyArray.new
        tmp_blobs << "first blob"
        before do
          allow(blob_service_client).to receive(:list_blobs).and_return(tmp_blobs)
        end
        it "returns blobs" do
          expect(blob_manager.list_blobs(container_name).size).to eq(1)
        end
      end

      context "when blob service client returns continuation_token" do
        tmp1 = MyArray.new
        tmp1 << "first blob"
        tmp1.continuation_token = "fake token"
        tmp2 = MyArray.new
        tmp2 << "second blob"
        before do
          allow(blob_service_client).to receive(:list_blobs).
            with(container_name, {}).and_return(tmp1)
          allow(blob_service_client).to receive(:list_blobs).
            with(container_name, {:marker => "fake token"}).and_return(tmp2)
        end
        it "returns blobs" do
          expect(blob_manager.list_blobs(container_name).size).to eq(2)
        end
      end
    end

  end  

  describe "#snapshot_blob" do
  end  
end
