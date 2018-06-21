require "capybara"
require "miniproxy"
require "support/capybara_driver"

RSpec.describe "miniproxy" do
  let(:session) { Capybara::Session.new(:firefox) }

  describe "http request" do

    context "stubbed" do
      before do
        MiniProxy::Server.stub_request(method: "GET", url: /example.com/, response: { body: "foo" })
      end

      after do
        MiniProxy::Server.reset
      end

      it "intercepts the request and returns the mock response" do
        session.visit("http://example.com/resource.txt")
        expect(session).to have_content "foo"
      end
    end

    context "not stubbed" do
      it "intercepts the request and prints a warning to stdout", :pending do
        expect {
          session.visit("http://example.com")
        }.to output(/WARN/).to_stdout_from_any_process
      end
    end
  end

  describe "https request" do
    context "stubbed" do
      before do
        MiniProxy::Server.stub_request(method: "GET", url: /example.com/, response: { body: "foo" })
      end

      after do
        MiniProxy::Server.reset
      end

      it "intercepts the request and returns the mock response" do
        session.visit("https://example.com/resource.txt")
        expect(session).to have_content "foo"
      end
    end

    context "not stubbed" do
      it "intercepts the request and prints a warning to stdout", :pending do
        expect {
          session.visit("http://example.com")
        }.to output(/WARN/).to_stdout_from_any_process
      end
    end
  end
end