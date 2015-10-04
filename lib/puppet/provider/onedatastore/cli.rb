# OpenNebula Puppet provider for onedatastore
#
# License: APLv2
#
# Authors:
# Based upon initial work from Ken Barber
# Modified by Martin Alfke
#
# Copyright
# initial provider had no copyright
# Deutsche Post E-POST Development GmbH - 2014, 2015
#

require 'rubygems'
require 'nokogiri'

Puppet::Type.type(:onedatastore).provide(:cli) do
  desc "onedatastore provider"

  has_command(:onedatastore, "onedatastore") do
    environment :HOME => '/root', :ONE_AUTH => '/var/lib/one/.one/one_auth'
  end

  # @property_hash is allocated here
  mk_resource_methods

  def create
    Puppet.debug(__method__)

    file = Tempfile.new("onedatastore-#{resource[:name]}")
    builder = Nokogiri::XML::Builder.new do |xml|
        xml.DATASTORE do
            xml.NAME resource[:name]
            xml.TM_MAD resource[:tm]
            xml.TYPE resource[:type].to_s.upcase
            xml.SAFE_DIRS do
                xml.send(resource[:safe_dirs].join(' '))
            end if resource[:safe_dirs]
            xml.DS_MAD resource[:dm]
            xml.BRIDGE_LIST resource[:bridgelist]
            xml.CEPH_HOST resource[:cephhost]
            xml.STAGING_DIR resource[:stagingdir]
            xml.BASE_PATH do
                resource[:basepath]
            end if resource[:basepath]
        end
    end
    tempfile = builder.to_xml
    file.write(tempfile)
    file.close
    onedatastore('create', file.path)

    post_validate_change
    @property_hash[:ensure] = :present
  end

  def destroy
    self.debug "Deleting datastore #{resource[:name]}"
    onedatastore('delete', resource[:name])
    @property_hash.clear
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def self.instances
      datastores = Nokogiri::XML(onedatastore('list','-x')).root.xpath('/DATASTORE_POOL/DATASTORE').map
      datastores.collect do |datastore|
        new(
            :name       => datastore.xpath('./NAME').text,
            :ensure     => :present,
            :type       => datastore.xpath('./TEMPLATE/TYPE').text,
            :dm         => (datastore.xpath('./TEMPLATE/DS_MAD').text unless datastore.xpath('./TEMPLATE/DS_MAD').nil?),
            :safe_dirs  => (datastore.xpath('./TEMPLATE/SAFE_DIRS').text unless datastore.xpath('./TEMPLATE/SAFE_DIRS').nil?),
            :tm         => (datastore.xpath('./TEMPLATE/TM_MAD').text unless datastore.xpath('./TEMPLATE/TM_MAD').nil?),
            :basepath   => (datastore.xpath('./TEMPLATE/BASE_PATH').text unless datastore.xpath('./TEMPLATE/BASE_PATH').nil?),
            :bridgelist => (datastore.xpath('./TEMPLATE/BRIDGE_LIST').text unless datastore.xpath('./TEMPLATE/BRIDGE_LIST').nil?),
            :cephhost   => (datastore.xpath('./TEMPLATE/CEPH_HOST').text unless datastore.xpath('./TEMPLATE/CEPH_HOST').nil?),
            :stagingdir => (datastore.xpath('./TEMPLATE/STAGING_DIR').text unless datastore.xpath('./TEMPLATE/STAGING_DIR').nil?),
            :disktype   => {'0' => 'file', '1' => 'block', '3' => 'rbd'}[datastore.xpath('./DISK_TYPE').text]
        )
      end
  end

  def self.prefetch(resources)
    datastores = instances
    resources.keys.each do |name|
      if provider = datastores.find{ |datastore| datastore.name == name }
        resources[name].provider = provider
      end
    end
  end

  def current_status()
    host = Nokogiri::XML(onedatastore('show', resource[:name], '-x')).root.xpath('DATASTORE')
    # required target status is 0 which corresponds to 'ready'
    return host.xpath('.STATE').text.to_i
  end

  def post_validate_change()
    Puppet.debug(__method__)

    # check current state against target state
    # see https://github.com/OpenNebula/one/blob/master/include/Datastore.h
    # ll. 68ff.
    #
    # enum DatastoreState
    # {
    #     READY     = 0, /** < Datastore ready to use */
    #     DISABLED  = 1  /** < System Datastore can not be used */
    # };
    #
    # command returns very quickly, so treating DISABLED/1 as a failure condition
    # is unnecessary (and could lead to false negatives)

    attempts = 0
    attempts_max = 3
    sleep_time = 30
    status_success = 0 

    status = current_status()
    while status != status_success do
      Puppet.debug("#{__method__}: validation in progress (attempt #{attempts}; current status #{status}; required status #{status_success})")

      attempts += 1

      # failure condition #1: attempts used up
      if attempts > attempts_max
        Puppet.debug("#{__method__}: attempts_max exceeded")
        raise "Failed to apply resource; resource status is #{status}" 
      end

      #failure condition #2: resource in defined failed state 
      #implementation TODO

      sleep sleep_time
      status = current_status()
    end
    Puppet.debug("#{__method__}: validation successful")
  end

  #setters
  def type=(value)
      raise "Can not modify type. You need to delete and recreate the datastore"
  end

  def dm=(value)
      raise "Can not modify ds_mad. You need to delete and recreate the datastore"
  end

  def tm=(value)
      raise "Can not modify tm_mad. You need to delete and recreate the datastore"
  end

  def disktype=(value)
      raise "Can not modify disktype. You need to delete and recreate the datastore"
  end

  def basepath=(value)
      raise "Can not modify basepath. You need to delete and recreate the datastore"
  end
end
