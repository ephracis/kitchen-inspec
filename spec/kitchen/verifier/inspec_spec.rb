# encoding: utf-8
#
# Author:: Fletcher Nichol (<fnichol@chef.io>)
# Author:: Christoph Hartmann (<chartmann@chef.io>)
#
# Copyright (C) 2015, Chef Software Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative "../../spec_helper"

require "logger"

require "kitchen/verifier/inspec"
require "kitchen/transport/ssh"
require "kitchen/transport/winrm"

describe Kitchen::Verifier::Inspec do

  let(:logged_output)     { StringIO.new }
  let(:logger)            { Logger.new(logged_output) }
  let(:config) do
    {
      kitchen_root: kitchen_root,
      test_base_path: File.join(kitchen_root, "test", "integration"),
    }
  end
  let(:transport_config)  { {} }
  let(:kitchen_root)      { Dir.mktmpdir }

  let(:platform) do
    instance_double("Kitchen::Platform", os_type: nil, shell_type: nil, name: "default")
  end

  let(:suite) do
    instance_double("Kitchen::Suite", name: "germany")
  end

  let(:transport) do
    instance_double(
      "Kitchen::Transport::Dummy",
      name: "wickedsauce",
      diagnose: transport_config
    )
  end

  let(:instance) do
    instance_double(
      "Kitchen::Instance",
      name: "coolbeans",
      logger: logger,
      platform: platform,
      suite: suite,
      transport: transport,
      to_str: "instance"
    )
  end

  before do
    allow(transport).to receive(:instance).and_return(instance)
  end

  after do
    FileUtils.remove_entry(kitchen_root)
  end

  let(:verifier) do
    Kitchen::Verifier::Inspec.new(config).finalize_config!(instance)
  end

  it "verifier api_version is 1" do
    expect(verifier.diagnose_plugin[:api_version]).to eq(1)
  end

  it "plugin_version is set to Kitchen::Verifier::INSPEC_VERSION" do
    expect(verifier.diagnose_plugin[:version])
      .to eq(Kitchen::Verifier::INSPEC_VERSION)
  end

  describe "configuration" do
    # nothing yet, woah!
  end

  describe "#finalize_config!" do
    let(:kitchen_inspec_tests) { File.join(kitchen_root, "test", "recipes") }
    context "when a test/recipes folder exists" do
      before do
        FileUtils.mkdir_p(kitchen_inspec_tests)
      end

      it "should read the tests from there" do
        expect(verifier[:test_base_path]).to eq(kitchen_inspec_tests)
      end
    end

    context "when a test/recipes folder does not exist" do
      it "should read the tests from the default location" do
        expect(verifier[:test_base_path]).to eq(File.join(kitchen_root, "test", "integration"))
      end
    end
  end

  context "with an ssh transport" do

    let(:transport_config) do
      {
        hostname: "boogie",
        port: "I shouldn't be used",
        username: "dance",
        ssh_key: "/backstage/pass",
        keepalive: "keepalive",
        keepalive_interval: "forever",
        connection_timeout: "nope",
        connection_retries: "thousand",
        connection_retry_sleep: "sleepy",
        max_wait_until_ready: 42,
        compression: "maxyo",
        compression_level: "pico",
      }
    end

    let(:transport) do
      Kitchen::Transport::Ssh.new(transport_config)
    end

    let(:runner) do
      instance_double("Inspec::Runner")
    end

    before do
      allow(runner).to receive(:add_target)
      allow(runner).to receive(:run).and_return 0
    end

    it "constructs a Inspec::Runner using transport config data and state" do
      config[:sudo] = "jellybeans"
      config[:sudo_command] = "allyourbase"

      expect(Inspec::Runner).to receive(:new)
        .with(
          hash_including(
            "backend" => "ssh",
            "logger" => logger,
            "sudo" => "jellybeans",
            "sudo_command" => "allyourbase",
            "host" => "boogie",
            "port" => 123,
            "user" => "dance",
            "keepalive" => "keepalive",
            "keepalive_interval" => "forever",
            "connection_timeout" => "nope",
            "connection_retries" => "thousand",
            "connection_retry_sleep" => "sleepy",
            "max_wait_until_ready" => 42,
            "compression" => "maxyo",
            "compression_level" => "pico",
            "key_files" => ["/backstage/pass"]
          )
        )
        .and_return(runner)

      verifier.call(port: 123)
    end

    it "constructs a Inspec::Runner using transport config data(host and port)" do
      config[:host] = "192.168.33.40"
      config[:port] = 222

      expect(Inspec::Runner).to receive(:new)
        .with(
          hash_including(
            "backend" => "ssh",
            "host" => "192.168.33.40",
            "port" => 222
          )
        )
        .and_return(runner)

      verifier.call(port: 123)
    end

    it "constructs an Inspec::Runner with a specified inspec output format" do
      config[:format] = "documentation"

      expect(Inspec::Runner).to receive(:new)
        .with(
          hash_including(
            "format" => "documentation"
          )
        )
        .and_return(runner)

      verifier.call(port: 123)
    end

    it "constructs an Inspec::Runner with a controls filter" do
      config[:controls] = %w{a control}

      expect(Inspec::Runner).to receive(:new)
        .with(
          hash_including(
            controls: %w{a control}
          )
        )
        .and_return(runner)

      verifier.call(port: 123)
    end

    it "provide platform and test suite to build output path" do
      allow(Inspec::Runner).to receive(:new).and_return(runner)

      expect(verifier).to receive(:runner_options).with(
          transport,
          {},
          "default",
          "germany"
      ).and_return({})
      verifier.call({})
    end

    it "custom inspec output path" do
      ensure_suite_directory("germany")
      config[:output] = "/tmp/inspec_results.xml"

      allow(Inspec::Runner).to receive(:new).and_return(runner)

      expect(runner).to receive(:add_target).with({ :path =>
        File.join(
          config[:test_base_path],
          "germany"
        ) }, hash_including(
          "output" => "/tmp/inspec_results.xml"
        ))

      verifier.call({})
    end

    it "resolve template format for inspec output path" do
      ensure_suite_directory("germany")
      config[:output] = "/tmp/%{platform}_%{suite}.xml"

      allow(Inspec::Runner).to receive(:new).and_return(runner)

      expect(runner).to receive(:add_target).with({ :path =>
        File.join(
          config[:test_base_path],
          "germany"
        ) }, hash_including(
          "output" => "/tmp/default_germany.xml"
        ))

      verifier.call({})
    end

    it "find test directory for runner" do
      ensure_suite_directory("germany")
      allow(Inspec::Runner).to receive(:new).and_return(runner)
      expect(runner).to receive(:add_target).with({ :path =>
        File.join(
          config[:test_base_path],
          "germany"
        ) }, anything)

      verifier.call({})
    end

    it "find test directory for runner if legacy" do
      create_legacy_test_directories
      allow(Inspec::Runner).to receive(:new).and_return(runner)
      expect(runner).to receive(:add_target).with({ :path =>
        File.join(
          config[:test_base_path],
          "germany", "inspec"
        ) }, anything)

      verifier.call({})
    end

    it "non-existent test directory for runner" do
      allow(Inspec::Runner).to receive(:new).and_return(runner)
      expect(runner).to_not receive(:add_target).with(
        File.join(
          config[:test_base_path],
          "nobody"
        ), anything)

      verifier.call({})
    end

    it "calls #run on the runner" do
      allow(Inspec::Runner).to receive(:new).and_return(runner)
      expect(runner).to receive(:run)

      verifier.call({})
    end
  end

  context "with an remote profile" do

    let(:transport) do
      Kitchen::Transport::Ssh.new({})
    end

    let(:runner) do
      instance_double("Inspec::Runner")
    end

    let(:suite) do
      instance_double("Kitchen::Suite", { name: "local" })
    end

    let(:instance) do
      instance_double(
        "Kitchen::Instance",
        name: "coolbeans",
        logger: logger,
        platform: platform,
        suite: suite,
        transport: transport,
        to_str: "instance"
      )
    end

    let(:config) do
      {
        inspec_tests: [{ :url => "https://github.com/nathenharvey/tmp_compliance_profile" }],
        kitchen_root: kitchen_root,
        test_base_path: File.join(kitchen_root, "test", "integration"),
      }
    end

    before do
      allow(runner).to receive(:add_target)
      allow(runner).to receive(:run).and_return 0
    end

    it "find test directory and remote profile" do
      ensure_suite_directory("local")
      allow(Inspec::Runner).to receive(:new).and_return(runner)
      expect(runner).to receive(:add_target).with({ :path =>
        File.join(config[:test_base_path], "local") }, anything)
      expect(runner).to receive(:add_target).with(
        { :url => "https://github.com/nathenharvey/tmp_compliance_profile" }, anything)
      verifier.call({})
    end
  end

  context "with an winrm transport" do

    let(:transport_config) do
      {
        username: "dance",
        password: "party",
        connection_retries: "thousand",
        connection_retry_sleep: "sleepy",
        max_wait_until_ready: 42,
      }
    end

    let(:transport) do
      Kitchen::Transport::Winrm.new(transport_config)
    end

    let(:runner) do
      instance_double("Inspec::Runner")
    end

    before do
      allow(runner).to receive(:add_target)
      allow(runner).to receive(:run).and_return 0
    end

    it "constructs a Inspec::Runner using transport config data and state" do
      expect(Inspec::Runner).to receive(:new)
        .with(
          hash_including(
            "backend" => "winrm",
            "logger" => logger,
            "host" => "win.dows",
            "port" => 123,
            "user" => "dance",
            "password" => "party",
            "connection_retries" => "thousand",
            "connection_retry_sleep" => "sleepy",
            "max_wait_until_ready" => 42,
            "color" => true
          )
        )
        .and_return(runner)

      verifier.call(hostname: "win.dows", port: 123)
    end

    it "constructs a Inspec::Runner using transport config data(host and port)" do
      config[:host] = "192.168.56.40"
      config[:port] = 22

      expect(Inspec::Runner).to receive(:new)
        .with(
          hash_including(
            "backend" => "winrm",
            "host" => "192.168.56.40",
            "port" => 22
          )
        )
        .and_return(runner)

      verifier.call(hostname: "win.dows", port: 123)
    end
  end

  context "with an unsupported transport" do

    it "#call raises a UserError" do
      expect { verifier.call({}) }.to raise_error(Kitchen::UserError)
    end
  end

  def create_legacy_test_directories
    base = File.join(config[:test_base_path], "germany")
    FileUtils.mkdir_p(File.join(base, "inspec"))
    FileUtils.mkdir_p(File.join(base, "serverspec"))
  end

  def ensure_suite_directory(suitename)
    suite = File.join(config[:test_base_path], suitename)
    FileUtils.mkdir_p(suite)
  end
end
