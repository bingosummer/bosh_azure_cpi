require 'spec_helper'

describe Bosh::AzureCloud::BlobManager do
  let(:azure_properties) { mock_azure_properties }
  let(:azure_client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:blob_manager) { Bosh::AzureCloud::BlobManager.new(azure_properties, azure_client2) }

  let(:container_name) { "fake-container-name" }
  let(:blob_name) { "fake-blob-name" }
  let(:keys) { ["fake-key-1", "fake-key-2"] }

  before do
    allow(Bosh::AzureCloud::AzureClient2).to receive(:new).
      and_return(azure_client2)
    allow(azure_client2).to receive(:get_storage_account_keys_by_name).
      and_return(keys)
  end

  let(:azure_client) { instance_double(Azure::Client) }
  let(:blob_service) { instance_double(Azure::Blob::BlobService) }
  let(:host) { "https://#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}.blob.core.windows.net" }

  before do
    allow(azure_client).to receive(:storage_blob_host=)
    allow(azure_client).to receive(:storage_blob_host).and_return(host)
    allow(azure_client).to receive(:blobs).
      and_return(blob_service)
    allow(Azure).to receive(:client).
      with(storage_account_name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, storage_access_key: keys[0]).
      and_return(azure_client)
  end

  describe "#delete_blob" do
    it "delete the blob" do
      expect(blob_service).to receive(:delete_blob).
        with(container_name, blob_name, {
          :delete_snapshots => :include
        })

      blob_manager.delete_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
    end
  end

  describe "#get_blob_uri" do
    it "gets the uri of the blob" do
      expect(
        blob_manager.get_blob_uri(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
      ).to eq("#{host}/#{container_name}/#{blob_name}")
    end
  end  

  describe "#delete_blob_snapshot" do
    it "delete the blob snapshot" do
      snapshot_time = 10

      expect(blob_service).to receive(:delete_blob).
        with(container_name, blob_name, {
          :snapshot => snapshot_time
        })

      blob_manager.delete_blob_snapshot(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, snapshot_time)
    end
  end  

  describe "#create_page_blob" do
    file_path = "/tmp/fake_image"
    File.open(file_path, 'wb') { |f| f.write("Hello CloudFoundry!") }

    context "when uploading page blob succeeds" do
      before do
        allow(blob_service).to receive(:create_page_blob)
        allow(blob_service).to receive(:create_blob_pages)
      end

      it "raise no error" do
        expect {
          blob_manager.create_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, file_path, blob_name)        
        }.not_to raise_error
      end
    end

    context "when uploading page blob fails" do
      before do
        allow(blob_service).to receive(:create_page_blob).and_raise(StandardError)
      end

      it "raise an error" do
        expect {
          blob_manager.create_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, file_path, blob_name)        
        }.to raise_error /Failed to upload page blob/
      end
    end
  end  

  describe "#create_empty_vhd_blob" do
    context "when creating empty vhd blob succeeds" do
      before do
        allow(blob_service).to receive(:create_page_blob)
        allow(blob_service).to receive(:create_blob_pages)
      end

      it "raise no error" do
        expect {
          blob_manager.create_empty_vhd_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1)    
        }.not_to raise_error
      end
    end

    context "when creating empty vhd blob fails" do
      context "blob is not created" do
        before do
          allow(blob_service).to receive(:create_page_blob).and_raise(StandardError)
        end

        it "raise an error and do not delete blob" do
          expect(blob_service).not_to receive(:delete_blob)
          expect {
            blob_manager.create_empty_vhd_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1)    
          }.to raise_error /Failed to create empty vhd blob/
        end
      end

      context "blob is created" do
        before do
          allow(blob_service).to receive(:create_page_blob)
          allow(blob_service).to receive(:create_blob_pages).and_raise(StandardError)
        end

        it "raise an error and delete blob" do
          expect(blob_service).to receive(:delete_blob)
          expect {
            blob_manager.create_empty_vhd_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1)    
          }.to raise_error /Failed to create empty vhd blob/
        end
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
        allow(blob_service).to receive(:list_blobs).and_return(tmp_blobs)
      end

      it "returns empty blobs" do
        expect(blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name)).to be_empty
      end
    end

    context "when the container is not empty" do
      context "when blob service client returns no continuation_token" do
        tmp_blobs = MyArray.new
        tmp_blobs << "first blob"
        before do
          allow(blob_service).to receive(:list_blobs).and_return(tmp_blobs)
        end

        it "returns blobs" do
          expect(blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name).size).to eq(1)
        end
      end

      context "when blob service client returns continuation_token" do
        tmp1 = MyArray.new
        tmp1 << "first blob"
        tmp1.continuation_token = "fake token"
        tmp2 = MyArray.new
        tmp2 << "second blob"
        before do
          allow(blob_service).to receive(:list_blobs).
            with(container_name, {}).and_return(tmp1)
          allow(blob_service).to receive(:list_blobs).
            with(container_name, {:marker => "fake token"}).and_return(tmp2)
        end

        it "returns blobs" do
          expect(blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name).size).to eq(2)
        end
      end
    end

  end  

  describe "#snapshot_blob" do
    it "snapshots the blob" do
      snapshot_time = 10
      metadata = {}

      expect(blob_service).to receive(:create_blob_snapshot).
        with(container_name, blob_name, {
          :metadata => metadata
        }).
        and_return(snapshot_time)

      expect(
        blob_manager.snapshot_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, metadata)
      ).to eq(snapshot_time)
    end
  end
end
