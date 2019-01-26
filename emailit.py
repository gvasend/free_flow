import smtplib
from os.path import basename
from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import COMMASPACE, formatdate
from email.mime.image import MIMEImage

import argparse


parser = argparse.ArgumentParser(description='Send an email with optional attachments.')

parser.add_argument('--from_address',default='gvasend@gmail.com',help='From email address')
	
parser.add_argument('--to',required=True,help='To email address')

parser.add_argument('--subject',default='No Subject',help='Email subject line')
	
parser.add_argument('--text',default='No text',help='Text of the email message')

parser.add_argument('--file_attachment',default=None,help='Files to attach')

import scrape as sc

sc.all_options(parser)

args = sc.parse_args(parser)


gmail_user = 'gvasend@gmail.com'
gmail_password = 'Sieche06'
    
def send_mail(send_from, send_to, subject, text, files=None): 
        COMMASPACE = ', '

        # Create the container (outer) email message.
        msg = MIMEMultipart()
        msg['Subject'] = subject
        # me == the sender's email address
        # family = the list of all recipients' email addresses
        msg['From'] = send_from
        msg['To'] = COMMASPACE.join(send_to)
        msg.preamble = subject

        msg.attach(MIMEText(text,'html'))

        # Assume we know that the image files are all in PNG format
        print("files to upload:",files)
        for f in files or []:
            with open(f, "rb") as fil:
                part = MIMEApplication(
                    fil.read(),
                    Name=basename(f)
                )
                part['Content-Disposition'] = 'attachment; filename="%s"' % basename(f)
                msg.attach(part)

        # Send the email via our own SMTP server.
       
        try:  
            server = smtplib.SMTP_SSL('smtp.gmail.com', 465)
            server.ehlo()
            server.login(gmail_user, gmail_password)
            server.sendmail(send_from, send_to, msg.as_string())
            server.close()

            print('Email sent!!!')
        except:  
            print('Something went wrong...')


  
send_mail(args.from_address, [args.to], args.subject, args.text, [args.file_attachment])
