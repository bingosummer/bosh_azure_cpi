require "spec_helper"

describe Bosh::AzureCloud::NetworkConfigurator do

  let(:dynamic) { {"type" => "dynamic"} }
  let(:manual) {
    {
      "type" => "manual",
      "cloud_properties" =>
        {
          "subnet_name" => "bar",
          "virtual_network_name" => "foo"
        }
    }
  }
  let(:vip) { {"type" => "vip"} }

  it "should raise an error if the spec isn't a hash" do
    expect {
      Bosh::AzureCloud::NetworkConfigurator.new("foo")
    }.to raise_error ArgumentError
  end

  describe "#private_ip" do
    it "should extract private ip address for manual network" do
      spec = {}
      spec["network_a"] = manual
      spec["network_a"]["ip"] = "10.0.0.1"

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.private_ip).to eq("10.0.0.1")
    end

    it "should extract private ip address from manual network when there's also vip network" do
      spec = {}
      spec["network_a"] = vip
      spec["network_a"]["ip"] = "10.0.0.1"
      spec["network_b"] = manual
      spec["network_b"]["ip"] = "10.0.0.2"      

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.private_ip).to eq("10.0.0.2")
    end     
    
    it "should not extract private ip address for dynamic network" do
      spec = {}
      spec["network_a"] = dynamic
      spec["network_a"]["ip"] = "10.0.0.1"

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.private_ip).to be_nil
    end     
  end
  
  describe "network types" do

    it "should raise an error if both dynamic and manual networks are defined" do
      network_spec = {
          "network1" => dynamic,
          "network2" => manual
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "Must have exactly one dynamic or manual network per instance"
    end

    it "should raise an error if neither dynamic nor manual networks are defined" do
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new("network1" => vip)
      }.to raise_error Bosh::Clouds::CloudError, "Exactly one dynamic or manual network must be defined"
    end

    it "should raise an error if multiple vip networks are defined" do
      network_spec = {
          "network1" => vip,
          "network2" => vip
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "More than one vip network for 'network2'"
    end

    it "should raise an error if multiple dynamic networks are defined" do
      network_spec = {
          "network1" => dynamic,
          "network2" => dynamic
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "Must have exactly one dynamic or manual network per instance"
    end

    it "should raise an error if multiple manual networks are defined" do
      network_spec = {
          "network1" => manual,
          "network2" => manual
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "Must have exactly one dynamic or manual network per instance"
    end

    it "should raise an error if an illegal network type is used" do
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new("network1" => {"type" => "foo"})
      }.to raise_error Bosh::Clouds::CloudError, "Invalid network type 'foo' for Azure, " \
                        "can only handle 'dynamic', 'vip', or 'manual' network types"
    end
  end
end
