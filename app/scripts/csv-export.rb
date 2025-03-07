#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'csv'
require 'time'
require 'optparse'

class GitHubPRFetcher
  attr_reader :repo_owner, :repo_name, :token, :output_file, :page_size, :max_prs

  def initialize(options)
    @repo_owner = options[:owner]
    @repo_name = options[:repo]
    @token = options[:token]
    @output_file = options[:output] || "pr_data.csv"
    @page_size = options[:page_size] || 30
    @max_prs = options[:max_prs] || 100
  end

  def fetch_and_export
    pull_requests = fetch_merged_prs
    export_to_csv(pull_requests)
    puts "Successfully exported #{pull_requests.size} PRs to #{output_file}"
  end

  private

  def fetch_merged_prs
    puts "Fetching merged PRs for #{repo_owner}/#{repo_name}..."
    
    all_prs = []
    page = 1
    
    loop do
      url = URI("https://api.github.com/repos/#{repo_owner}/#{repo_name}/pulls?state=closed&per_page=#{page_size}&page=#{page}")
      
      response = make_request(url)
      prs = JSON.parse(response.body)
      
      break if prs.empty?
      
      # Filter for merged PRs and fetch additional details
      merged_prs = prs.select { |pr| pr["merged_at"] }
      
      merged_prs.each do |pr|
        pr_number = pr["number"]
        puts "Processing PR ##{pr_number}..."
        
        # Fetch PR details with files information
        pr_details_url = URI("https://api.github.com/repos/#{repo_owner}/#{repo_name}/pulls/#{pr_number}")
        pr_details_response = make_request(pr_details_url)
        pr_details = JSON.parse(pr_details_response.body)
        
        all_prs << pr_details
      end
      
      page += 1
      break if all_prs.size >= max_prs
    end
    
    all_prs
  end

  def make_request(url)
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(url)
    request["Accept"] = "application/vnd.github.v3+json"
    request["Authorization"] = "token #{token}" if token
    request["User-Agent"] = "GitHub-PR-Stats-Script"
    
    response = http.request(request)
    
    if response.code != "200"
      puts "Error: #{response.code} - #{response.body}"
      exit 1
    end
    
    response
  end

  def export_to_csv(pull_requests)
    CSV.open(output_file, "w") do |csv|
      # Write headers
      csv << [
        "PR Number",
        "Title",
        "Author Username",
        "Author Name",
        "Author Email",
        "Merger Username",
        "Merger Name",
        "Merger Email",
        "Additions",
        "Deletions",
        "Created At",
        "Merged At",
        "Time to Merge (hours)"
      ]
      
      # Write data
      pull_requests.each do |pr|
        created_at = Time.parse(pr["created_at"])
        merged_at = Time.parse(pr["merged_at"])
        time_to_merge_hours = ((merged_at - created_at) / 3600).round(2)
        
        author = pr["user"]
        merger = pr["merged_by"] || pr["user"] # Fallback to author if merger info not available
        
        csv << [
          pr["number"],
          pr["title"],
          author["login"],
          author["name"] || "N/A", # GitHub API doesn't include name in this response
          "N/A", # Email not available in this API response
          merger["login"],
          merger["name"] || "N/A",
          "N/A", # Email not available in this API response
          pr["additions"],
          pr["deletions"],
          created_at.iso8601,
          merged_at.iso8601,
          time_to_merge_hours
        ]
      end
    end
  end
end

# Parse command line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: pr_stats.rb [options]"
  
  opts.on("-o", "--owner OWNER", "Repository owner (username or organization)") { |v| options[:owner] = v }
  opts.on("-r", "--repo REPO", "Repository name") { |v| options[:repo] = v }
  opts.on("-t", "--token TOKEN", "GitHub API token") { |v| options[:token] = v }
  opts.on("-f", "--output FILE", "Output CSV file (default: pr_data.csv)") { |v| options[:output] = v }
  opts.on("-p", "--page-size SIZE", Integer, "Number of PRs per page (default: 30)") { |v| options[:page_size] = v }
  opts.on("-m", "--max-prs COUNT", Integer, "Maximum number of PRs to fetch (default: 100)") { |v| options[:max_prs] = v }
  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Validate required options
[:owner, :repo].each do |required|
  unless options[required]
    puts "Error: Missing required option --#{required}"
    exit 1
  end
end

# Run the fetcher
GitHubPRFetcher.new(options).fetch_and_export