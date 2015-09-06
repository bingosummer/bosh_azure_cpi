module Bosh::AzureCloud
  class DiskManager
    DISK_CONTAINER       = 'bosh'
    DISK_PREFIX          = 'bosh-disk'
    PREMIUM_DISK_PREFIX  = 'bosh-disk-premium'

    include Bosh::Exec
    include Helpers

    def initialize(blob_manager)
      @blob_manager = blob_manager
      @logger = Bosh::Clouds::Config.logger
    end

    def delete_disk(disk_name)
      @logger.info("delete_disk(#{disk_name})")
      @blob_manager.delete_blob(DISK_CONTAINER, "#{disk_name}.vhd", is_premium_disk(disk_name)) if has_disk?(disk_name)
    end

    def delete_vm_status_files(prefix)
      @logger.info("delete_vm_status_files(#{prefix})")
      blobs = @blob_manager.list_blobs(DISK_CONTAINER, prefix).select{
        |blob| blob.name =~ /status$/
      }
      blobs.each do |blob|
        @blob_manager.delete_blob(DISK_CONTAINER, blob.name)
      end
    rescue => e
      @logger.debug("delete_vm_status_files - error: #{e.message}\n#{e.backtrace.join("\n")}")
    end

    def snapshot_disk(disk_name, metadata)
      @logger.info("snapshot_disk(#{disk_name}, #{metadata})")
      snapshot_disk_name = "#{DISK_PREFIX}-#{SecureRandom.uuid}"
      if is_premium_disk(disk_name)
        snapshot_disk_name = "#{PREMIUM_DISK_PREFIX}-#{SecureRandom.uuid}"
      end
      caching = get_caching(disk_name)
      snapshot_disk_name += "-#{caching}"
      @blob_manager.snapshot_blob(DISK_CONTAINER, "#{disk_name}.vhd", metadata, "#{snapshot_disk_name}.vhd", is_premium_disk(disk_name))
      snapshot_disk_name
    end

    ##
    # Creates a disk (possibly lazily) that will be attached later to a VM.
    #
    # @param [Integer] size disk size in GB
    # @return [String] disk name
    def create_disk(size, cloud_properties)
      @logger.info("create_disk(#{size})")
      disk_name = "#{DISK_PREFIX}-#{SecureRandom.uuid}"
      if !cloud_properties.nil? && cloud_properties.has_key?('type')
        if cloud_properties['type'] == 'premium'
          disk_name = "#{PREMIUM_DISK_PREFIX}-#{SecureRandom.uuid}"
        elsif cloud_properties['type'] != 'standard'
          cloud_error("Unknown disk type #{cloud_properties['type']}")
        end
      end
      if !cloud_properties.nil? && cloud_properties.has_key?('caching')
        if cloud_properties['caching'] == 'None'
          disk_name += '-None'
        elsif cloud_properties['caching'] == 'ReadOnly'
          disk_name += '-ReadOnly'
        elsif cloud_properties['caching'] == 'ReadWrite'
          disk_name += '-ReadWrite'
        else
          cloud_error("Unknown disk caching #{cloud_properties['caching']}")
        end
      else
        disk_name += '-None'
      end
      @logger.info("Start to create an empty vhd blob: blob_name: #{disk_name}.vhd")
      @blob_manager.create_empty_vhd_blob(DISK_CONTAINER, "#{disk_name}.vhd", size, is_premium_disk(disk_name))
      disk_name
    end

    def has_disk?(disk_name)
      @logger.info("has_disk?(#{disk_name})")
      @blob_manager.blob_exist?(DISK_CONTAINER, "#{disk_name}.vhd", is_premium_disk(disk_name))
    end

    def get_disk_uri(disk_name)
      @logger.info("get_disk_uri(#{disk_name})")
      @blob_manager.get_blob_uri(DISK_CONTAINER, "#{disk_name}.vhd", is_premium_disk(disk_name))
    end

    def is_premium_disk(disk_name)
      disk_name.start_with?(PREMIUM_DISK_PREFIX)
    end

    def get_caching(disk_name)
      caching = 'None'
      if disk_name.end_with?('ReadOnly')
        caching = 'ReadOnly'
      elsif disk_name.end_with?('ReadWrite')
        caching = 'ReadWrite'
      end
      caching
    end
  end
end