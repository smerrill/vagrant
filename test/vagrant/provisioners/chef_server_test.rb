require "test_helper"

class ChefServerProvisionerTest < Test::Unit::TestCase
  setup do
    @klass = Vagrant::Provisioners::ChefServer

    @action_env = Vagrant::Action::Environment.new(vagrant_env.vms[:default].env)

    @config = @klass::Config.new
    @action = @klass.new(@action_env, @config)
    @env = @action.env
    @vm = @action.vm
  end

  context "provisioning" do
    should "run the proper sequence of methods in order" do
      prov_seq = sequence("prov_seq")
      @action.expects(:verify_binary).with("chef-client").once.in_sequence(prov_seq)
      @action.expects(:chown_provisioning_folder).once.in_sequence(prov_seq)
      @action.expects(:create_client_key_folder).once.in_sequence(prov_seq)
      @action.expects(:upload_validation_key).once.in_sequence(prov_seq)
      @action.expects(:setup_json).once.in_sequence(prov_seq)
      @action.expects(:setup_server_config).once.in_sequence(prov_seq)
      @action.expects(:run_chef_client).once.in_sequence(prov_seq)
      @action.provision!
    end
  end

  context "preparing" do
    setup do
      File.stubs(:file?).returns(true)
    end

    should "not raise an exception if validation_key_path is set" do
      @config.validation_key_path = "7"
      @config.chef_server_url = "7"

      assert_nothing_raised { @action.prepare }
    end

    should "raise an exception if validation_key_path is nil" do
      @config.validation_key_path = nil

      assert_raises(Vagrant::Provisioners::Chef::ChefError) {
        @action.prepare
      }
    end

    should "not raise an exception if validation_key_path does exist" do
      @config.validation_key_path = vagrantfile(tmp_path)
      @config.chef_server_url = "7"

      assert_nothing_raised { @action.prepare }
    end

    should "raise an exception if validation_key_path doesn't exist" do
      @config.validation_key_path = "7"
      @config.chef_server_url = "7"

      File.expects(:file?).with(@action.validation_key_path).returns(false)
      assert_raises(Vagrant::Provisioners::Chef::ChefError) {
        @action.prepare
      }
    end

    should "not raise an exception if chef_server_url is set" do
      @config.validation_key_path = vagrantfile(tmp_path)
      @config.chef_server_url = "7"

      assert_nothing_raised { @action.prepare }
    end

    should "raise an exception if chef_server_url is nil" do
      @config.chef_server_url = nil

      assert_raises(Vagrant::Provisioners::Chef::ChefError) {
        @action.prepare
      }
    end
  end

  context "creating the client key folder" do
    setup do
      @raw_path = "/foo/bar/baz.pem"
      @config.client_key_path = @raw_path

      @path = Pathname.new(@raw_path)
    end

    should "create the folder using the dirname of the path" do
      ssh = mock("ssh")
      ssh.expects(:exec!).with("sudo mkdir -p #{@path.dirname}").once
      @vm.ssh.expects(:execute).yields(ssh)
      @action.create_client_key_folder
    end
  end

  context "uploading the validation key" do
    should "upload the validation key to the provisioning path" do
      @action.expects(:validation_key_path).once.returns("foo")
      @action.expects(:guest_validation_key_path).once.returns("bar")
      @vm.ssh.expects(:upload!).with("foo", "bar").once
      @action.upload_validation_key
    end
  end

  context "the validation key path" do
    should "expand the configured key path" do
      result = mock("result")
      File.expects(:expand_path).with(@config.validation_key_path, @env.root_path).once.returns(result)
      assert_equal result, @action.validation_key_path
    end
  end

  context "the guest validation key path" do
    should "be the provisioning path joined with validation.pem" do
      result = mock("result")
      File.expects(:join).with(@config.provisioning_path, "validation.pem").once.returns(result)
      assert_equal result, @action.guest_validation_key_path
    end
  end

  context "generating and uploading chef client configuration file" do
    setup do
      @action.stubs(:guest_validation_key_path).returns("foo")
    end

    should "call setup_config with proper variables" do
      @action.expects(:setup_config).with("chef_server_client", "client.rb", {
        :node_name => @config.node_name,
        :chef_server_url => @config.chef_server_url,
        :validation_client_name => @config.validation_client_name,
        :validation_key => @action.guest_validation_key_path,
        :client_key => @config.client_key_path
      })

      @action.setup_server_config
    end
  end

  context "running chef client" do
    setup do
      @ssh = mock("ssh")
      @vm.ssh.stubs(:execute).yields(@ssh)
    end

    should "cd into the provisioning directory and run chef client" do
      @ssh.expects(:exec!).with("cd #{@config.provisioning_path} && sudo -E chef-client -c client.rb -j dna.json").once
      @action.run_chef_client
    end

    should "check the exit status if that is given" do
      @ssh.stubs(:exec!).yields(nil, :exit_status, :foo)
      @ssh.expects(:check_exit_status).with(:foo, anything).once
      @action.run_chef_client
    end
  end
end