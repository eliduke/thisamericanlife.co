require 'nokogiri'
require 'open-uri'
require 'date'
require 'bunny_cdn'

# uncommit for dev purposes
require 'dotenv/load'
# require 'pry'

BunnyCdn.configure do |config|
  config.apiKey = ENV['BUNNY_API_KEY']
  config.storageZone = "thisamericanlife"
  config.region = "la"
  config.accessKey = ENV['BUNNY_ACCESS_KEY']
end

last_episode_id = Dir["_episodes/*"].last.split("/").last.split(".").first.to_i
new_episode_id = last_episode_id + 1

begin
  doc    = Nokogiri::HTML(URI.open("https://tal.fm/#{new_episode_id}"))
  header = doc.css('.episode-header')
  slug   = "%04d" % new_episode_id

  if File.exist?("_episodes/#{slug}.html")
    puts "Episode #{new_episode_id} has already been imported."
    return
  end

  if header.css('.download').css('a').empty?
    available_when_text = header.css('.download').children.first.to_s.strip
    puts "Episode #{new_episode_id} is not quite ready. #{available_when_text}."
    return
  end

  puts "IMPORTING NEW EPISODE #{new_episode_id}!\n"
  puts "* Scraping meta data..."

  date  = Date.parse(header.css('.date-display-single').children.to_s).strftime('%F')
  title = header.css('.episode-title').css('h1').children.to_s
  body  = header.css('.field-name-body').css('p').children.to_s.gsub(/<[^>]*>/,'')
  mp3   = header.css('.download').css('a')[0]['href'].split('?').first
  image = if doc.css('.tal-episode-image').nil?
    doc.at("meta[property='og:image']")['content']
  else
    doc.css('.tal-episode-image').css('img')[0]['src'].split('?').first
  end

  puts "* Uploading audio file..."
  URI.open(mp3) do |audio|
    path = "#{slug}.mp3"
    File.open(path, "wb") { |file| file.write(audio.read) }
    if BunnyCdn::Storage.uploadFile('audios', path)
      File.delete(path)
    end
  end

  puts "* Uploading image file..."
  URI.open(image) do |image|
    path = "#{slug}.jpg"
    File.open(path, "wb") { |file| file.write(image.read) }
    if BunnyCdn::Storage.uploadFile('images', path)
      File.delete(path)
    end
  end

  puts "* Creating episode file..."
  File.open("./_episodes/#{slug}.html", "wb") do |file|
    file.write(<<~EOS
    ---
    layout: episode
    number: #{new_episode_id}
    slug: "#{slug}"
    title: #{title}
    description: >
      #{body}
    date: #{date}
    ---
    EOS
    )
  end

  puts "EPISODE #{new_episode_id} WAS IMPORTED SUCCESSFULLY!\n"
rescue OpenURI::HTTPError => e
  if e.message == '404 Not Found'
    puts "Episode #{new_episode_id} doesn't exist yet."
  else
    raise e
  end
end
