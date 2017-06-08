#!/usr/bin/env ruby
require 'rb-scpt'
require 'osax'
require 'nokogiri'
require 'fuzzy_match'

include Appscript
include OSAX

UNREDEEMED_KEYS_PATH = File.expand_path '~/unredeemed-steam-keys.txt'
REDEEMED_KEYS_PATH = File.expand_path '~/redeemed-steam-keys.txt'
FAILED_KEYS_PATH = File.expand_path '~/failed-steam-keys.txt'

def activate_keys
  return unless validate_browser

  keys = read_keys

  return unless keys.length > 0

  licensed_items = []

  message =  "Steam will lock you out from redeeming keys if you enter too many keys for a Steam items you already own!\n\nCross-reference keys against Steam items you've already licensed?"

  if display_dialog(message, buttons: ['No', 'Yes'], default_button: 2)[:button_returned] == 'Yes'
    loop do
      licensed_items = read_licensed_items

      break if licensed_items.length > 0

      button = display_dialog('Could not find any licensed items.', buttons: ['Quit', 'Continue anyway', 'Try again'], default_button: 3)[:button_returned]

      return if button == 'Quit'
      break if button == 'Continue anyway'
    end
  end

  previously_unredeemed_keys = parse_key_file UNREDEEMED_KEYS_PATH
  previously_redeemed_keys = parse_key_file REDEEMED_KEYS_PATH
  previously_failed_keys = parse_key_file FAILED_KEYS_PATH
  previously_encountered_keys = previously_unredeemed_keys.merge(previously_redeemed_keys).merge!(previously_redeemed_keys)

  fuzzy_items = FuzzyMatch.new licensed_items

  # Determine whether or not we should skip redemption of certain keys.

  redeemable_keys = {}
  skipped_keys = {}
  unsure_keys = {}

  keys.each do |key, title|
    if previously_encountered_keys[key]
      skipped_keys[key] = title
    else
      title = title.gsub(/ Steam key/i, '')
      dlc = title.include?('DLC')
      options = {
        threshold: dlc ? 0.9 : 0.75,
        find_best: dlc
      }

      match = fuzzy_items.find(title, options)
      match = fuzzy_items.find(title + " Retail", options) unless match || dlc
      match = fuzzy_items.find(title.gsub(' DLC', ''), options) unless match || !dlc

      if match
        if dlc && /^.+[0-9]$/.match(match[0]) && !title.include?(match[0])
          unsure_keys[key] = title
        else
          skipped_keys[key] = title
        end
      else
        options[:threshold] *= 0.8

        match = fuzzy_items.find(title, options)
        match = fuzzy_items.find(title + " Retail", options) unless match || dlc
        match = fuzzy_items.find(title.gsub(' DLC', ''), options) unless match || !dlc

        if match
          unsure_keys[key] = title
        else
          redeemable_keys[key] = title
        end
      end
    end
  end

  if skipped_keys.length > 0
    message = "We're going to skip the following items, as you've probably already redeemed them:\n\n"

    skipped_keys.each do |key, title|
      message << title
      message << "\n"
    end

    message << "\nWe'll save these to #{UNREDEEMED_KEYS_PATH}, so you have a record."

    if display_dialog(message, buttons: ['No, let me decide', 'OK'], default_button: 2)[:button_returned] != 'OK'
      unsure_keys.merge!(skipped_keys)
      skipped_keys = {}
    end
  end

  unsure_keys.each do |key, title|
    message = "Would you like to redeem the following item?\n\n#{title}\n#{key}"
    if display_dialog(message, buttons: ['No', 'Yes'], default_button: 2)[:button_returned] == 'Yes'
      redeemable_keys[key] = title
    else
      skipped_keys[key] = title
    end
  end

  loop do
    break if redeemable_keys.length == 0

    message = "We're going to redeem the following items:\n\n"

    redeemable_keys.each do |key, title|
      message << title
      message << "\n"
    end

    break if display_dialog(message, buttons: ['No, let me pick', "OK"], default_button: 2)[:button_returned] == 'OK'

    unsure_keys = redeemable_keys
    redeemable_keys = {}

    unsure_keys.each do |key, title|
      message = "Would you like to redeem the following item?\n\n#{title}\n#{key}"
      if display_dialog(message, buttons: ['No', 'Yes'], default_button: 2)[:button_returned] == 'Yes'
        redeemable_keys[key] = title
      else
        skipped_keys[key] = title
      end
    end
  end

  if skipped_keys.length > 0
    File.open(UNREDEEMED_KEYS_PATH, 'a+') do |file|
      skipped_keys.reject { |key, title| previously_unredeemed_keys[key] }.each do |key, title|
        file.puts "#{key} - #{title}"
      end
    end
  end

  if redeemable_keys.length == 0
    display_dialog "Looks like there are no new keys to be redeemed", buttons: ['OK'], default_button: 1
    return
  end

  # Try redeem the keys the user has chosen to redeem.
  # Note: We append to our record keeping files as we go in case we crash etc.

  redeemed_keys = {}
  failed_keys = {}

  redeemable_keys.each do |key, title|
    if redeem_key key
      redeemed_keys[key] = title

      unless previously_redeemed_keys[key]
        File.open(REDEEMED_KEYS_PATH, 'a+') do |file|
          file.puts "#{key} - #{title}"
        end
      end
    else
      failed_keys[key] = title

      message = "Failed to redeem #{title} with #{key}\n\nPlease read the information in Steam, and decide whether or not you'd like to continue (by skipping this key)."
      return if display_dialog(message, buttons: ['Quit', 'Continue'], default_button: 2)[:button_returned] != 'Continue'

      unless previously_failed_keys[key]
        File.open(FAILED_KEYS_PATH, 'a+') do |file|
          file.puts "#{key} - #{title}"
        end
      end
    end
  end

  # Although we've already taken care of appending keys to record files, we need to remove
  # out-dated entries (inconsistencies) e.g. previously unredeemed, since been redeemed.

  all_redeemed_keys = previously_redeemed_keys.merge redeemed_keys
  all_failed_keys = previously_failed_keys.merge(failed_keys).reject { |k, t| all_redeemed_keys[k] }
  all_unredeemed_keys = previously_unredeemed_keys.merge(skipped_keys).reject { |k, t| all_redeemed_keys[k] || all_failed_keys[k] }

  overwrite_keys_file FAILED_KEYS_PATH, all_failed_keys
  overwrite_keys_file UNREDEEMED_KEYS_PATH, all_unredeemed_keys

  # Provide a status report

  if failed_keys.length > 0
    message = "The following items failed to be redeemed:\n\n"

    failed_keys.each do |key, title|
      message << title
      message << "\n"
    end

    message << "\nWe've saved these to #{FAILED_KEYS_PATH}, so you have a record."

    display_dialog message, buttons: ['OK'], default_button: 1
  end

  display_dialog "Sucessfully redeemed #{redeemed_keys.length} new items!\n\nFor your records we've added the redeemed keys to #{REDEEMED_KEYS_PATH}", buttons: ['OK'], default_button: 1
end

def redeem_key(key)
  system_events.launch

  steam_application.activate
  steam_process = system_events.processes['Steam'].get

  sleep 0.5

  # Close open windows

  loop do
    window_count = steam_process.windows.get.length
    system_events.keystroke('w', {:using => :'command_down'})
    sleep 1

    break if window_count == steam_process.windows.get.length
  end

  # Activation process

  osax.set_the_clipboard_to key
  sleep 0.5

  steam_process.menu_bars[1].menu_bar_items['Games'].menus.menu_items['Activate a Product on Steam...'].click
  sleep 2

  2.times do
    system_events.keystroke "\r"
    sleep 0.5
  end

  # Steam are doing their own modifier key tracking, we have to first press command, then tap v
  system_events.key_down :command
  sleep 0.5

  system_events.keystroke 'v'
  sleep 0.5

  system_events.key_up :command
  sleep 0.5

  system_events.keystroke "\r"
  sleep 2

  5.times do
    window_names = steam_process.windows.get.map { |w| w.name.get.to_s }

    if window_names.detect { |n| n.start_with?('Steam') && n.include?('Error') }
      return false
    elsif window_names.detect { |n| n == 'Product Activation'}
      system_events.keystroke "\r"
      sleep 0.5
    elsif window_names.detect { |n| n.start_with? 'Install' }
      2.times do
        system_events.keystroke "\t"
        sleep 0.5
      end

      system_events.keystroke "\r"
      sleep 0.5
    else
      return true
    end
  end

  false
end

def overwrite_keys_file(path, keys)
  File.open(path, "w") do |file|
    keys.each do |key, title|
      file.puts "#{key} - #{title}"
    end
  end
end

def parse_key_file(path)
  keys = {}

  if File.exists? path
    File.open(path) do |file|
      file.each_line do |line|
        match = line.match "([A-Z0-9]+(?:-[A-Z0-9]+)+)\s+-\s+([^\s].+)"

        if match
          keys[match[1]] = match[2]
        end
      end
    end
  end

  keys
end

def validate_browser
  if browser.nil?
    button = display_dialog("Hmm, it doesn't look like Safari is running. Please launch it.",
      buttons: ['Quit', 'Try again'],
      default_button: 2)[:button_returned]

    if button == 'Try again'
      validate_browser
    else
      false
    end
  else
    true
  end
end

def open_browser_tab(url)
  system_events.launch
  browser.activate
  osax.set_the_clipboard_to url
  system_events.processes[browser_name].menu_bars[1].menu_bar_items['File'].menus.menu_items['New Tab'].click
  sleep 2

  system_events.keystroke('v', {:using => :'command_down'})
  sleep 0.5

  system_events.keystroke("\r")
  sleep 0.5
end

def read_licensed_items
  open_browser_tab 'https://store.steampowered.com/account/licenses/'

  loop do
    10.times do
      sleep 1
      break if browser_contents_loaded?
    end

    break if browser_contents.xpath("//*[@class='loginbox']").length == 0

    button = display_dialog("Looks like you haven't logged into Steam from your browser.\n\nYou can either login then press 'Continue', or 'Skip', which will proceed without taking into account items you've already licensed.",
      buttons: ['Skip', 'Continue'],
      default_button: 2)[:button_returned]

    return [] if button == 'Skip'
  end

  items = []

  10.times do
    sleep 1
    break if browser_contents_loaded?
  end

  sleep 1.5

  items = browser_contents.xpath("//table[@class='account_table']//tr[./td[@class='license_acquisition_col']]").map { |node|
    node.xpath('.//a').remove
    node.xpath('./td')[1].inner_text.strip
  }

  system_events.keystroke('w', {:using => :'command_down'})

  items
end

def read_keys
  contents = browser_contents

  browser_keys = Hash[contents.xpath("//*[contains(concat(' ', normalize-space(@class), ' '), ' sr-key ') and .//*[contains(@class, 'sr-redeemed')]]").map { |node|
    [
      node.xpath(".//*[@class='sr-redeemed']").first.inner_text.strip.split("\n").first,
      node.xpath(".//*[@class='sr-key-heading']").first.inner_text.strip
    ] if node.xpath(".//*[@class='sr-redeemed']").first && node.xpath(".//*[@class='sr-key-heading']").first
  }.compact.concat(contents.xpath("//*[./*[@class='game-name'] and .//*[contains(@class, 'redeemed')]]").map { |node|
    redeem_text = node.xpath(".//*[contains(@class, 'redeemed')]").first.inner_text.strip

    if redeem_text.match "[A-Z0-9]+(?:-[A-Z0-9]+)+"
      [
        redeem_text,
        node.xpath("./*[@class='game-name']").first.inner_text.strip.split("\n").first
      ]
    else
      nil
    end
  }).compact]

  if browser_keys.length == 0
    button = display_dialog("Unable to find any Humble Bundle Steam keys.\n\nPlease make sure your browser has some Humble Bundle keys displayed (you must click to redeem, that is not automated).",
      buttons: ['Quit', 'Try again'],
      default_button: 2)[:button_returned]

    if button == 'Try again'
      read_keys
    else
      {}
    end
  else
    browser_keys
  end
end

def steam_application
  @steam_application ||= app "/Applications/Steam.app"
end

def system_events
  @system_events ||= begin
    sys = app "System Events"
    sys.launch
    sys
  end
end

def browser_contents
  Nokogiri::HTML browser_html
end

def browser_contents_loaded?
  browser.documents[1].do_JavaScript('document.readyState') == 'complete'
end

def browser_html
  browser.documents[1].do_JavaScript('document.body.innerHTML') rescue ''
end

def browser_name
  browser.name.get
end

def browser
  @browser ||= begin
    app "Safari"
  end
end

def application_is_running?(app_name)
  app_name && app(app_name).is_running?
end

def default_browser
  @default_browser ||= app.by_id browser_bundle_identifier
end

def browser_bundle_identifier
  preferences_path = osax.path_to(:preferences).to_s
  `/usr/libexec/PlistBuddy -c 'Print :LSHandlers' #{preferences_path}/com.apple.LaunchServices/com.apple.launchservices.secure.plist | grep 'LSHandlerURLScheme = http$' -C 2 | grep 'LSHandlerRoleAll = ' | cut -d '=' -f 2 | tr -d ' '`.chomp
end

def display_dialog(*args)
  osax.activate
  osax.display_dialog *args
end

# Do it
activate_keys
