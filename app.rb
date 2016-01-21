require 'webhook_handler'
require 'octokit'
require 'open-uri'

class PullRequestReview
  include WebhookHandler

  def perform(repository_full_name, number)
    pull_request = github.pull_request(repository_full_name, number)
    files = github.pull_request_files(repository_full_name, number)
    ep_popolo = files.find_all { |file| file[:filename].match(/ep-popolo-v1.0\.json$/) }
    stats = {}
    ep_popolo.each do |file|
      # Get the JSON and parse it
      before = JSON.parse(open(file[:raw_url].sub(pull_request[:head][:sha], pull_request[:base][:sha])).read)
      after = JSON.parse(open(file[:raw_url]).read)
      %w[persons organizations].each do |collection|
        stats[file] ||= {}
        stats[file][collection] ||= {}
        before_ids = before[collection].map { |item| item['id'] }
        after_ids = after[collection].map { |item| item['id'] }
        logger.info "collection=#{collection} added=#{(after_ids - before_ids).size} removed=#{(before_ids - after_ids).size}"

        stats[file][collection]['added'] = after_ids - before_ids
        stats[file][collection]['removed'] = before_ids - after_ids
      end
    end
    p stats
  end

  def handle_webhook
    return unless request.env['HTTP_X_GITHUB_EVENT'] == 'pull_request'
    request.body.rewind
    payload = JSON.parse(request.body.read)
    return unless payload['repository']['full_name'] == everypolitician_data_repo
    return unless %w(opened synchronize).include?(payload['action'])
    self.class.perform_async(payload['repository']['full_name'], payload['number'])
  end

  private

  def github
    @github ||= Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])
  end

  def everypolitician_data_repo
    ENV.fetch('EVERYPOLITICIAN_DATA_REPO', 'everypolitician/everypolitician-data')
  end
end
