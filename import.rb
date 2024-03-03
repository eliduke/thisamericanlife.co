require 'nokogiri'
require 'open-uri'
require 'date'
require 'pry'
require 'bunny_cdn'
require 'dotenv/load'

BunnyCdn.configure do |config|
  config.apiKey = ENV['BUNNY_API_KEY']
  config.storageZone = "thisamericanlife"
  config.region = "la"
  config.accessKey = ENV['BUNNY_ACCESS_KEY']
end

last_episode_id = Dir["_episodes/*"].last.split("/").last.split(".").first.to_i

input_ids = if ARGV.empty?
  [last_episode_id + 1]
else
  ARGV
end

if input_ids.empty?
  puts "You must provide at least one episode id (from thisamericanlife.org), like this:\n\n"
  puts "$ ruby import.rb 824\n\n"
  puts "Or you can provide multiple ids at once, like this:\n\n"
  puts "$ ruby import.rb 824 825 826\n\n"
  return
end

input_ids.each do |id|
  begin
    doc    = Nokogiri::HTML(URI.open("https://tal.fm/#{id}"))
    header = doc.css('.episode-header')
    slug   = "%04d" % id

    if File.exist?("_episodes/#{slug}.html")
      puts "Episode #{id} has already been imported."
      return
    end

    if header.css('.download').css('a').empty?
      available_when_text = header.css('.download').children.first.to_s.strip
      puts "Episode #{id} is not quite ready. #{available_when_text}."
      return
    end

    puts "IMPORTING NEW EPISODE #{id}!\n"
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

    URI.open(mp3) do |audio|
      puts "* Uploading audio file..."
      path = "tmp/#{slug}.mp3"
      File.open(path, "wb") { |file| file.write(audio.read) }
      if BunnyCdn::Storage.uploadFile('tmp', path)
        File.delete(path)
      end
    end

    URI.open(image) do |image|
      puts "* Uploading image file..."
      path = "tmp/#{slug}.jpg"
      File.open(path, "wb") { |file| file.write(image.read) }
      if BunnyCdn::Storage.uploadFile('tmp', path)
        File.delete(path)
      end
    end

    puts "* Creating episode file..."
    File.open("_episodes/#{slug}.html", "wb") do |file|
      file.write(<<~EOS
      ---
      layout: episode
      number: #{id}
      slug: "#{slug}"
      title: #{title}
      description: >
        #{body}
      date: #{date}
      ---
      EOS
      )
    end

    puts "EPISODE #{id} WAS IMPORTED SUCCESSFULLY!\n"
  rescue OpenURI::HTTPError => e
    if e.message == '404 Not Found'
      puts "Episode #{id} doesn't exist yet."
    else
      raise e
    end
  end
end
