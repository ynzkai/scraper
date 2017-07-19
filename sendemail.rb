require 'net/smtp'

filename = "/tmp/test.txt"
# Read a file and encode it into base64 format
filecontent = File.read(filename)
encodedcontent = [filecontent].pack("m")   # base64

marker = "AUNIQUEMARKER"

body = <<EOF
This is a test email to send an attachement.
EOF

# Define the main headers.
part1 = <<EOF
From: Private Person <ynzkai@gmail.com>
To: A Test User <zk24@sina.com>
Subject: Sending Attachement
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary = #{marker}

--#{marker}
EOF

# Define the message action
part2 = <<EOF
Content-Type: text/plain
Content-Transfer-Encoding:8bit

#{body}
--#{marker}
EOF

# Define the attachment section
part3 = <<EOF
Content-Type: multipart/mixed; name = \"#{filename}\"
Content-Transfer-Encoding:base64
Content-Disposition: attachment; filename = "#{filename}"

#{encodedcontent}
--#{marker}--
EOF

mailtext = part1 + part2 + part3

# Let's put our code in safe area
begin 
  smtp = Net::SMTP.new('smtp.gmail.com', 465)
  smtp.enable_ssl
  smtp.start('gmail.com', 'ynzkai@gmail.com', 'zk810327', :login) do |smtp|
    smtp.sendmail(mailtext, 'ynzkai@gmail.com', ['zk24@sina.com'])
  end
rescue Exception => e  
  print "Exception occured: " + e.message
end  
