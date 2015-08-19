require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient2 do
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:azure_client2) {
    Bosh::AzureCloud::AzureClient2.new(
      mock_cloud_options["properties"]["azure"],
      logger
    )
  }
  let(:subscription_id) { mock_azure_properties['subscription_id'] }
  let(:api_version) { mock_azure_properties['api_version'] }
  let(:resource_group) { mock_azure_properties['resource_group_name'] }
  let(:request_id) { "fake-request-id" }

  let(:token_uri) { "https://login.windows.net/#{subscription_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:vm_name) { "fake-vm-name" }
  let(:valid_access_token) { "valid-access-token" }
  let(:invalid_access_token) { "invalid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#create_virtual_machine" do
    let(:vm_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version}&validating=true" }

    let(:vm_params) do
      {
        :name                => vm_name, 
        :location            => "b",
        :vm_size             => "c",
        :username            => "d",
        :custom_data         => "e",
        :image_uri           => "f",
        :os_disk_name        => "g",
        :os_vhd_uri          => "h",
        :ssh_cert_data       => "i"
      }
    end
    let(:network_interface) { {:id => "a"} }

    context "when token is valid, create operation is accepted and completed" do
      it "should raise no error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Succeeded"}',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interface)
        }.not_to raise_error
      end

      # TODO
      it "should raise no error if restart operation is InProgress at first and Succeeded finally" do
      end
    end

    context "when token is invalid" do
      it "should raise an error if token is not gotten" do
        stub_request(:post, token_uri).to_return(
          :status => 404,
          :body => '',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interface)
        }.to raise_error /get_token - http error: 404/
      end

      it "should raise an error if tenant id, client id or client secret is invalid" do
        stub_request(:post, token_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interface)
        }.to raise_error /get_token - Azure authentication failed: invalid tenant id, client id or client secret./
      end

      it "should raise an error if authentication retry fails" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interface)
        }.to raise_error /Azure authentication failed: Token is invalid./
      end

      # TODO
      it "should not raise an error if authentication retry succeeds" do
      end
    end

    context "when create operation is not accepted" do
      it "should raise an error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 404,
          :body => 'create operation does not return 200 or 201',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interface)
        }.to raise_error /create operation does not return 200 or 201/
      end
    end

    context "when token is valid, restart operation is accepted and not completed" do
      it "should raise an error if operation_status_link is null" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 200,
          :body => '{}',
          :headers => {})
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Succeeded"}',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interface)
        }.to raise_error /check_completion - operation_status_link cannot be null./
      end

      it "should raise an error if check completion operation is not accepeted" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 404,
          :body => '',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interface)
        }.to raise_error /check_completion - http error: 404/
      end

      it "should raise an error if create peration failed" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Failed"}',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interface)
        }.to raise_error /status: Failed/
      end

      # TODO
      it "should cause an endless loop if restart operation is always InProgress" do
      end
    end
  end
end
