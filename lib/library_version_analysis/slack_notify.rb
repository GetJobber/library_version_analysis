require 'slack-ruby-client'

module LibraryVersionAnalysis
  class SlackNotify
    def self.notify(message, room = "test_engineering")
      # client = Slack::Web::Client.new(:token => Rails.configuration.x.slackbot.api_key)
      client = Slack::Web::Client.new(token: ENV['SLACK_TOKEN'], ca_file: "/usr/lib/ssl/certs/Amazon_Root_CA_1.pem")

      begin
        client.chat_postMessage({
                                  :channel => room,
                                  :text => message,
                                  :as_user => true,
                                  :link_names => true,
                                  :unfurl_links => false,
                                  :unfurl_media => false
                                })
      rescue Slack::Web::Api::Errors::SlackError => e
        if ["channel_not_found", "not_in_channel"].include? e.message
          error_msg = "Could not post to slack channel: #{room}."
          error_msg << " Please make sure channel exists and Jobber Bot has been invited."
          log_exception(e, error_msg)
        else
          raise e
        end
      end
    end
  end
end
