#!/usr/bin/env ruby
# Adds the Resources/output_story folder as a folder reference to all targets'
# Copy Bundle Resources so YAML/videos are bundled at runtime.

require 'xcodeproj'

PROJECT_PATH = 'bigpinkcat.swift/bigpinkcat.swift.xcodeproj'
GROUP_NAME = 'bigpinkcat.swift Shared'
FOLDER_REL_PATH = 'Resources/output_story' # relative to GROUP_NAME
FOLDER_NAME = 'output_story'               # visible name in Xcode

project = Xcodeproj::Project.open(PROJECT_PATH)

shared_group = project.main_group[GROUP_NAME]
abort("Group '#{GROUP_NAME}' not found") unless shared_group

# Find existing folder reference (blue folder) if present
file_ref = shared_group.children.find do |child|
  child.isa == 'PBXFileReference' && (child.path == FOLDER_REL_PATH || child.name == FOLDER_NAME)
end

unless file_ref
  file_ref = shared_group.new_file(FOLDER_REL_PATH, :group)
  # Mark as a folder reference (blue folder)
  if file_ref.respond_to?(:set_explicit_file_type)
    file_ref.set_explicit_file_type('folder')
  else
    file_ref.explicit_file_type = 'folder'
  end
  file_ref.name = FOLDER_NAME
  puts "Added folder reference: #{FOLDER_REL_PATH}"
end

project.targets.each do |target|
  rbp = target.resources_build_phase
  refs = rbp.files_references
  if refs.include?(file_ref)
    puts "  - #{FOLDER_NAME} already in Resources of target: #{target.name}"
  else
    rbp.add_file_reference(file_ref, true)
    puts "  - Added #{FOLDER_NAME} to Resources of target: #{target.name}"
  end
end

project.save
puts 'Project saved.'
