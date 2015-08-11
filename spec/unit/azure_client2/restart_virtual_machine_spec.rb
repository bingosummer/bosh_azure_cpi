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

  describe "#restart_virtual_machine" do
    let(:vm_restart_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}/restart?api-version=#{api_version}" }

    context "when token is valid, restart operation is accepted and completed" do
      it "should raise no error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          :status => 202,
          :body => '{}',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Succeeded"}',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
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
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error /get_token - http error: 404/
      end

      it "should raise an error if authentication retry fails" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error /Azure authentication failed: Token is invalid./
      end

      # TODO
      it "should not raise an error if authentication retry succeeds" do
      end
    end

    context "when token is valid, restart operation is not accepted" do
      it "should raise an error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          :status => 404,
          :body => 'restart is not accepted',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error /message: restart is not accepted/
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
        stub_request(:post, vm_restart_uri).to_return(
          :status => 202,
          :body => '{}',
          :headers => {})
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Succeeded"}',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error /check_completion - operation_status_link cannot be null./
      end

      it "should raise an error if check completion operation is not acceptted" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          :status => 202,
          :body => '{}',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 404,
          :body => '',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error /check_completion - http error: 404/
      end

      it "should raise an error if restart operation failed" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          :status => 202,
          :body => '{}',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Failed"}',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error /status: Failed/
      end

      # TODO
      it "should cause an endless loop if restart operation is always InProgress" do
      end
    end
  end
end
