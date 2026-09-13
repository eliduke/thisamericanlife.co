require 'front_matter_parser'

Dir['_episodes/*'].last(71).each do |ep|  
  parsed = FrontMatterParser::Parser.parse_file(ep)
  number = parsed['number']
  title  = parsed['title']
  desc   = parsed['description'].chomp
  date   = parsed['date']

  puts <<~EOS
    { number: #{number}, title: %^#{title}^, description: %^#{desc}^, date: "#{date}" },
  EOS
  
  # run this in the commandline, then copy and paste the output into seeds.rb
end
