require 'aws/s3'

module AP
  class Replay

    def initialize
      @s3_config = YAML.load_file("#{$dir}/config/s3.yml")
      $replaydone = false
    end

    def init
      connect
      bucket = AWS::S3::Bucket.find(@s3_config['bucket'])
      data_dir = "#{$dir}/data/"

      $params[:replaydate] = bucket.objects(:prefix => "ap/").map{|o| o.key.split('/')[1, 1].first}.uniq.sort.last.split('.').first unless $params[:replaydate]
      local_gzip = "#{data_dir}#{$params[:replaydate]}.tar.gz"
      unless File.exist?(local_gzip)
        puts "Downloading replay from #{$params[:replaydate]}..."
        s3_object = bucket.objects(:prefix => "ap/#{$params[:replaydate]}.tar.gz").first
        File.open(local_gzip, 'w') {|f| f.write(s3_object.value)}
        system "tar -zxvf #{local_gzip} -C #{data_dir}"
      end

      @timekeys = Dir.glob("#{data_dir}#{$params[:replaydate]}/*").map{|d| d.split('/').last}.uniq.sort
      @timekey_idx = 0
    end

    def replay_all
      #connect
      #bucket = AWS::S3::Bucket.find(@s3_config['bucket'])

      timekey = @timekeys[@timekey_idx]
      $l.log "Started replaying #{timekey}"

      archive_dir = "#{$dir}/data/#{$params[:replaydate]}/#{timekey}"
      new_states = Dir.glob("#{archive_dir}/*").map{|d| d.split('/').last}.uniq
      if $params[:states]
        new_states = new_states & $params[:states]
      end

      new_states.each do |state_abbr|
        state_dir = "#{$dir}/../../tmp/ap/#{state_abbr}"
        system "mkdir -p #{state_dir}"
        state_archive_dir = "#{archive_dir}/#{state_abbr}"
        files = ["#{state_abbr}_Results.txt", "#{state_abbr}_Race.txt", "#{state_abbr}_Candidate.txt"]
        files.each do |file|
          archive_file = "#{state_archive_dir}/#{file.split('/').last}"
          next unless File.exists?(archive_file)
          local_file = "#{state_dir}/#{file.split('/').last}"
          system("cp #{archive_file} #{local_file}")
          $new_files << [local_file, nil, nil]
        end
        $updated_states << state_abbr unless $updated_states.include?(state_abbr)
      end

      @timekey_idx += 1
      $replaydone = true if @timekey_idx >= @timekeys.size
      $l.log "Finished replaying"
    end

    def record_all
      $l.log "Started recording"
      dt1 = Time.now.strftime('%Y%m%d')
      dt2 = Time.now.strftime('%H%M%S')
      $updated_states.each do |state_abbr|
        record_state(state_abbr, $new_files.select{|file| file.first.index("#{state_abbr}_")}, dt1, dt2)
      end
      $l.log "Finished recording"
    end

  private

    def record_state(state_abbr, files, dt1, dt2)
      connect
      archive_dir = "#{$dir}/data/#{dt1}/#{dt2}/#{state_abbr}/"
      system "mkdir -p #{archive_dir}"
      files.each do |file|
        archive_file = "#{archive_dir}#{file.first.split('/').last}"
        system "cp #{file.first} #{archive_file}"
        s3_file = "ap/#{dt1}/#{dt2}/#{state_abbr}/#{file.first.split('/').last}"
        AWS::S3::S3Object.store(s3_file, open(file.first), @s3_config['bucket'], :content_type => MIME::Types.type_for(file.first).join(', '), :access => :private)
      end
    end

    def connect
      AWS::S3::Base.establish_connection!(:access_key_id => @s3_config['access_key_id'], :secret_access_key => @s3_config['secret_access_key'])
    end

  end
end