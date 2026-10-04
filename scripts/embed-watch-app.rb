#!/usr/bin/env ruby
# Embeds the Watch app in the iPhone app, so installing the iPhone app on a
# real phone also installs the Watch app on its paired watch.
#
# It isn't done by default because with the Watch app embedded, Xcode refuses
# to build the iPhone app for ANY destination - including the iPhone
# simulator - until the watchOS platform is installed (Xcode > Settings >
# Components). Run this once that's installed:
#
#   cd ios/FitnessTracker && ruby ../../scripts/embed-watch-app.rb
#
# (needs the `xcodeproj` gem: gem install xcodeproj)
require 'xcodeproj'

proj = Xcodeproj::Project.open('FitnessTracker.xcodeproj')
app = proj.targets.find { |t| t.name == 'FitnessTracker' }
watch = proj.targets.find { |t| t.name == 'FitnessTrackerWatch' }
abort 'FitnessTracker or FitnessTrackerWatch target not found - run from ios/FitnessTracker' unless app && watch
abort 'Already embedded.' if app.copy_files_build_phases.any? { |p| p.name == 'Embed Watch Content' }

app.add_dependency(watch)
embed = app.new_copy_files_build_phase('Embed Watch Content')
embed.symbol_dst_subfolder_spec = :products_directory
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
embed.add_file_reference(watch.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
proj.save
puts 'Watch app embedded in the iPhone app.'
