require 'vagrant/util/subprocess'

module Vagrant
  module Driver
    # This class contains the logic to drive VirtualBox.
    class VirtualBox
      # Include this so we can use `Subprocess` more easily.
      include Vagrant::Util

      # The version of virtualbox that is running.
      attr_reader :version

      def initialize
        # Read and assign the version of VirtualBox we know which
        # specific driver to instantiate.
        begin
          @version = read_version
        rescue Subprocess::ProcessFailedToStart
          # This means that VirtualBox was not found, so we raise this
          # error here.
          raise Errors::VirtualBoxNotDetected
        end
      end

      # Imports the VM with the given path to the OVF file. It returns
      # the UUID as a string.
      def import(ovf)
        output = execute("import", ovf)
        if output =~ /VM name "(.+?)"/
          name = $1.to_s
          output = execute("list", "vms")
          if output =~ /^"#{name}" {(.+?)}$/
            return $1.to_s
          end
        end

        nil
      end

      # This deletes the VM with the given name.
      def delete(uuid)
        execute("unregistervm", uuid, "--delete")
      end

      # This reads the guest additions version for a VM.
      def guest_additions_version(uuid)
        output = execute("guestproperty", "get", uuid, "/VirtualBox/GuestAdd/Version")
        return $1.to_s if output =~ /^Value: (.+?)$/
        return nil
      end

      # This reads the state for the given UUID. The state of the VM
      # will be returned as a symbol.
      def read_state(uuid)
        output = execute("showvminfo", uuid, "--machinereadable")
        if output =~ /^name="<inaccessible>"$/
          return :inaccessible
        elsif output =~ /^VMState="(.+?)"$/
          return $1.to_sym
        end

        nil
      end

      protected

      # This returns the version of VirtualBox that is running.
      #
      # @return [String]
      def read_version
        execute("--version").split("r")[0]
      end

      # Execute the given subcommand for VBoxManage and return the output.
      def execute(*command)
        # TODO: Detect failures and handle them
        r = Subprocess.execute("VBoxManage", *command)
        if r.exit_code != 0
          raise Exception, "FAILURE: #{r.stderr}"
        end
        r.stdout
      end
    end
  end
end
