#!/usr/bin/env ruby

# Script to add new Swift files to Xcode project
require 'xcodeproj'

project_path = 'bigpinkcat.swift.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the Shared group
shared_group = project.main_group['bigpinkcat.swift Shared']

# Files to add
files_to_add = [
  'GameDataModels.swift',
  'YAMLParser.swift',
  'GameDataLoader.swift',
  'VisualNovelScene.swift'
]

# Add files to the Shared group
files_to_add.each do |filename|
  file_path = "bigpinkcat.swift Shared/#{filename}"

  # Check if file already exists in group
  existing_file = shared_group.files.find { |f| f.path == filename }

  if existing_file
    puts "File #{filename} already in project"
  else
    # Add file reference
    file_ref = shared_group.new_reference(file_path)
    puts "Added #{filename} to project"

    # Add to all targets
    project.targets.each do |target|
      target.add_file_references([file_ref])
      puts "  - Added to target: #{target.name}"
    end
  end
end

# Save the project
project.save
puts "\nProject saved successfully!"
