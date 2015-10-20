require 'cloud/azure'
require 'json'

MOCK_AZURE_SUBSCRIPTION_ID = 'aa643f05-5b67-4d58-b433-54c2e9131a59'
MOCK_DEFAULT_STORAGE_ACCOUNT_NAME = '8853f441db154b438550a853'
MOCK_AZURE_STORAGE_ACCESS_KEY = '3e795106-5887-4342-8c73-338facbb09fa'
MOCK_RESOURCE_GROUP_NAME = '352ec9c1-6dd5-4a24-b11e-21bbe3d712ca'
MOCK_AZURE_TENANT_ID = 'e441d583-68c5-46b3-bf43-ab49c5f07fed'
MOCK_AZURE_CLIENT_ID = '62bd3eaa-e231-4e13-8baf-0e2cc8a898a1'
MOCK_AZURE_CLIENT_SECRET = '0e67d8fc-150e-4cc0-bbf3-087e6c4b9e2a'
MOCK_SSH_CERT = 'bar'

def mock_cloud_options
  {
    'plugin' => 'azure',
    'properties' => {
      'azure' => {
        'environment' => 'AzureCloud',
        'subscription_id' => MOCK_AZURE_SUBSCRIPTION_ID, 
        'storage_account_name' => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
        'resource_group_name' => MOCK_RESOURCE_GROUP_NAME,
        'tenant_id' => MOCK_AZURE_TENANT_ID,
        'client_id' => MOCK_AZURE_CLIENT_ID,
        'client_secret' => MOCK_AZURE_CLIENT_SECRET,
        'ssh_user' => 'vcap',
        'ssh_certificate' => MOCK_SSH_CERT,
        'parallel_upload_thread_num' => 16
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

def mock_registry_properties
  mock_cloud_options['properties']['registry']
end

def mock_registry
  registry = double('registry',
    :endpoint => mock_registry_properties['endpoint'],
    :user     => mock_registry_properties['user'],
    :password => mock_registry_properties['password']
  )
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

