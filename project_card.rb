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
project_card = Sawyer::Resource.new(github.agent, payload['project_card'])
return if project_card.content_url.nil?
issue_number = project_card.content_url.split('/').last
project = project_card.rels[:project].get(headers: preview_header)

labels = {
  'created' => Set.new,
  'deleted' => Set.new
}

col_to_label = {
  'Triage' => 's:triage',
  'Stuck' => 's:hold',
  'Stalled' => 's:stalled',
  'To do' => 's:available',
  'In progress' => 's:in-progress',
  'Design in progress' => 's:design-in-progress',
  'Review in progress' => 's:review-in-progress'
}


mutually_exclusive_labels = {}
[
  %w(sprint backlog),
  %w(t:bug t:discussion t:seminar t:event t:meeting),
  %w(s:triage s:hold s:stalled s:available s:in-progress s:design-in-progress s:review-in-progress)
].each do |group|
  group.each do |label|
    mutually_exclusive_labels[label] = group - [label]
  end
end

case payload['action']
when 'created', 'deleted'
  case project.name
  when /^[12]\./
    labels[payload['action']] << 'sprint'
  when /^[45]\./
    labels[payload['action']] << 'backlog'
  when /Bugs/
    labels[payload['action']] << 't:bug'
  when /Discussion/
    labels[payload['action']] << 't:discussion'
  when /Meeting/
    issue = project_card.rels[:content].get
    if issue.name.include?('[Seminar]')
      labels[payload['action']] << 't:seminar'
    elsif issue.name.include?('[Event]')
      labels[payload['action']] << 't:event'
    else
      labels[payload['action']] << 't:meeting'
    end
  when /Someday/
    labels[payload['action']] << 's:someday'
  end
end

if payload['action'] != 'deleted'
  column = project_card.rels[:column].get(headers: preview_header)
  label = col_to_label[column]
  if !label.nil?
    labels['created'] << label
  end
end

labels['created'].each do |added|
  removed = mutually_exclusive_labels[added]
  if !removed.nil?
    labels['deleted'] .merge(removed)
  end
end

if labels['created'].size > 0
  github.add_labels_to_an_issue(repo_id, issue_number, labels['created'].to_a)
end

if labels['deleted'].size > 0
  existing_labels = github.labels_for_issue(repo_id, issue_number).map(&:name)
  labels['deleted'] = labels['deleted'] & existing_labels
end

labels['deleted'].each do |label|
  begin
    github.remove_label(repo_id, issue_number, label)
  rescue Octokit::NotFound
    # ignore
  end
end
