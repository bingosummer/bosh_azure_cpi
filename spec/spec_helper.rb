require 'cloud/azure'

MOCK_AZURE_SUBSCRIPTION_ID = 'foo'
MOCK_AZURE_TENANT_ID = 'foo'
MOCK_AZURE_CLIENT_ID = 'foo'
MOCK_AZURE_CLIENT_SECRET = 'foo'
MOCK_AZURE_STORAGE_ACCESS_KEY = 'foo'
MOCK_SSH_CERT = 'bar'

def mock_cloud_options
  {
    'plugin' => 'azure',
    'properties' => {
      'azure' => {
        'environment' => 'AzureCloud',
        'api_version' => '2015-05-01-preview',
        'subscription_id' => MOCK_AZURE_SUBSCRIPTION_ID, 
        'storage_account_name' => 'mock_storage_name',
        'storage_access_key' => MOCK_AZURE_STORAGE_ACCESS_KEY,
        'resource_group_name' => 'mock_resource_group',
        'tenant_id' => MOCK_AZURE_TENANT_ID,
        'client_id' => MOCK_AZURE_CLIENT_ID,
        'client_secret' => MOCK_AZURE_CLIENT_SECRET,
        'ssh_user' => 'vcap',
        'ssh_certificate' => MOCK_SSH_CERT,
      },
      'registry' => {
        'endpoint' => 'localhost:42288',
        'user' => 'admin',
        'password' => 'admin'
      },
      'agent' => {
        'blobstore' => {
          'address' => '10.0.0.5'
        },
        'nats' => {
          'address' => '10.0.0.5'
        }
      }
    }
  }
end

def mock_azure_properties
  mock_cloud_options['properties']['azure']
end

def mock_registry(endpoint = 'http://registry:3333')
  registry = double('registry', :endpoint => endpoint)
  allow(Bosh::Registry::Client).to receive(:new).and_return(registry)
  registry
end

def mock_cloud(options = nil)
  Bosh::AzureCloud::Cloud.new(options || mock_cloud_options['properties'])
end

RSpec.configure do |config|
  config.before do
    logger = Logger.new('/dev/null')
    allow(Bosh::Clouds::Config).to receive(:logger).and_return(logger)
  end
end

