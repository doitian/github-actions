#!/usr/bin/env ruby

require 'json'
require 'octokit'
require 'set'

github = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
github.auto_paginate = true
preview_header = { accept: 'application/vnd.github.inertia-preview+json' }

payload = File.open(ENV['GITHUB_EVENT_PATH']) do |f|
  JSON.load(f)
end

repo_id = payload['repository']['id']

before = after = nil
case payload['action']
when 'edited'
  case payload['changes']['name']['from']
  when /^[12]\./
    before = 'sprint'
  when /^[45]\./
    before = 'backlog'
  end
  case payload['project']['name']
  when /^[12]\./
    after = 'sprint'
  when /^[45]\./
    after = 'backlog'
  end

  if before != after
    puts "==> change all cards in #{payload['project']['name']}: #{before} => #{after}"
    project = Sawyer::Resource.new(github.agent, payload['project'])
    project.rels['columns'].get(headers: preview_header).data.each do |col|
      col.rels['cards'].get(headers: preview_header).data.each do |card|
        issue_number = card.content_url.split('/').last
        if !before.nil?
          github.remove_label(repo_id, issue_number, before)
        end
        if !after.nil?
          github.add_labels_to_an_issue(repo_id, issue_number, [after])
        end
      end
    end
  end
end
