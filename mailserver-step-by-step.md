
#Postfix + IMAP-Dovecot from scratch

This tutorial is intended for creating a very basic yet working configuration for Postfix and Dovecot when you have no experience with both programs so far. It is meant as a kickoff for further configuration extensions and that you understand what is actually going on. To keep it simple, information for user accounts are not stored in a SQL database, that we don't have to deal with all the database stuff.

The goal of this tutorial is to set up a mail server for multiple users who get access to the server through IMAP, like when you are responsible to install a mail server for a small company with just a handful of employees.

##Overview

The tasks of the mail server are distributed across the two programs Postfix and Dovecot.

Postfix handles the transport of mails. It waits for incoming mails and forwards these to another server. This happens in two directions: Mails coming from the internet directed to our domain are forwarded to the Dovecot server and thus the recipients' mailboxes. And mails coming from our users are forwarded to mail servers on the internet. A combination of both is local mail delivery, when one of our users wants to send a mail to another user, Postfix accepts a mail from the local user and forwards it to Dovecot and the local mailbox.

Dovecot is the manager of the mailboxes. On the one hand it waits for incoming mails forwarded by Postfix to deliver it to the addressed mailbox. On the other hand it offers an IMAP interface to the user, who can access his mailbox with a mail client.

The protocol for transporting mails over the internet is SMTP. The protocol for accessing user mailboxes from mail clients is IMAP. We will have to do with a third protocol, which is used for the transport from Postfix to Dovecot, named LMTP.

##Prerequisites

Before we can start configuring our mail server, some work has to be done before, which is not explained here how it is done, and some conditions must be met.

The mail server needs to be run on a machine with direct internet access, that means it must have a public IP address (or your NATted network is configured so that the public IP address is mapped to this machine), the ports 25, 143 and 993 must be reachable from the internet.

The public IP address must be static.

The DNS records for this machine have to be configured correctly. If for example the machine has the public IP address 172.28.45.212 (actually this is not a public address, but it's just an example), the domain under which you want to receive email is "MAILDOMAIN" and the mail server machine should have the name "MAILHOST.MAILDOMAIN", DNS must be configured so that

- The A record for "MAILHOST.MAILDOMAIN" points to address 172.28.45.212

- The MX record for "MAILDOMAIN" points to "MAILHOST.MAILDOMAIN"

- The reverse IP entry for 172.28.45.212 points to "MAILHOST.MAILDOMAIN"

The reverse entry is required because some mail servers on the internet perform checks on the IP addresses where the check for the reverse entry is part of.

During the construction of the configuration files in this tutorial, for the tests we need an external machine somewhere on the internet, not in the same network as the mail server machine. We will use the program 'telnet' on this machine.

An existing mail account is required, where we can send test mails to.

##Names used in this tutorial

- The domain we want to install the mail server for is "MAILDOMAIN"

- The machine for the name server is "MAILHOST.MAILDOMAIN"

- The mail account we will create is "MAILUSER<span></span>@MAILDOMAIN"

- The external machine on the internet from where we do some tests is "EXTHOST.EXTDOMAIN"

- The existing mail account for test mails is "EXTUSER<span></span>@EXTDOMAIN"

In your configurations, you should replace the example names with real, valid names. Especially the external mail address must be owned by you.

When we start a command in the terminal, the prompt shows on which machine we are: "MAILROOT<span></span>@MAILHOST" means the command is run on "MAILHOST.MAILDOMAIN", and "EXTUSER<span></span>@EXTHOST" is run on "EXTHOST.EXTDOMAIN".

##Installation

On Debian, the required packages are installed as root with

>`MAILROOT@MAILHOST# apt-get install postfix dovecot-core dovecot-imapd dovecot-lmtpd mutt telnet`

Some dialoges may appear during the installation, you can simply confirm the default settings.

'mutt' is a mail client for a terminal and is only needed during the tutorial. If you prefer another client, you can use it. And after the configuration, 'mutt' can be removed again, if you want to.

'telnet' is used for some tests, where we simulate an SMTP or IMAP client on the console.

##First steps with Postfix

You may have heard that administrating a mail server is a difficult job, and that you have the fear of configuring something wrong, that your mail server becomes a spam distributor. Postfix helps in the way that the default settings are on the safe side. We use this circumstance by starting with an empty configuration file, that you don't have to care about the confusing settings in the default configuration.

The two main Postfix configuration files are '/etc/postfix/master.cf' and '/etc/postfix/main.cf'.

'master.cf' contains the configuration for the various Postfix processes which handle the mail transport, that means which program should be run for a particular task and which parameters it should have. Although this is an important file for Postfix, fortunately it does not need to be modified by us. The default configuration is sufficient.

'main.cf' is the configuration file in which we will do all the modifications.

Let's start with a blank 'main.cf'. Create a backup copy of the original configuration file and make the new file completely empty:

>
`MAILROOT@MAILHOST# cd /etc/postfix`
`MAILROOT@MAILHOST# mv main.cf main.cf.bak`
`MAILROOT@MAILHOST# > main.cf`


In case dovecot was started after the installation, make sure it is not running until later:

>`MAILROOT@MAILHOST# service dovecot stop`

After the Postfix configuration was changed, Postfix needs to be restarted. The init script could be used, but the command 'postfix' gives management access to Postfix, too, so we use it:

>`MAILROOT@MAILHOST# postfix reload`

The log file should show something like this:

>
`MAILROOT@MAILHOST# tail /var/log/syslog`
`...`
`Mar 29 13:52:39 MAILHOST postfix/postfix-script[8083]: refreshing the Postfix mail system`
`Mar 29 13:52:39 MAILHOST postfix/master[2464]: reload -- version 2.9.6, configuration /etc/postfix`
`...`

The server is now running and is ready to accept mails for delivery. For a first try, we will send a mail from root on the mail server to root on the mail server and see what happens (enter "Test 1" and "." manually):

>
`MAILROOT@MAILHOST# sendmail root`
**`Test 1`**
**`.`**

The single "." ends the email and does not get part of the email.

When we look at '/var/log/syslog', some messages show the handling of the mail. And when opening a mail client like 'mutt' or 'mail', a new mail without a subject and the body "Test 1" should have arrived.

##Architecture and concepts

Before doing some more experiments sending and receiving emails, we take a look at the architecture of Postfix. When you look at Postfix as a black box, there are some input and output ports through which mail is transferred.

The input ports are waiting for incoming mails. Each input port implements a different mail protocol (at least for the understanding in this tutorial). Incoming mails are either rejected by Postfix, this means these mails do not get past the input ports, or mails are accepted and handled by the Postfix black box.

Output ports implement different mail protocols, too. They care about sending emails coming from inside the Postfix black box to the outer world, or about placing a mail directly into a receiver's mailbox.

The input section of Postfix is displayed in the first diagram in

http://www.postfix.org/OVERVIEW.html

The interesting parts are 'smtpd', the receiver for mails over SMTP, and 'sendmail', a receiver for mails which are sent from the same machine with the program 'sendmail'. Actually, we will deal almost only with 'smtpd' throughout this tutorial.

The diagram may look a little complicated, but unless we want to know the internals of Postfix, we just need to notice 'smtpd' and 'sendmail' as the entrance points to Postfix.

The output section of Postfix is displayed in the second diagram on the same page. The components we are going to deal with are 'smtp' for outgoing mails over SMTP, 'lmtp' for outgoing mails over LMTP (we will use this for the connection to Dovecot later), and 'local' for the direct delivery of mails into a user's mailbox. Again, the other components can be ignored for this tutorial.

The main purpose of Postfix is to accept mails coming in through one of the input ports and to route it to one of the output ports for further delivery. Another task of Postfix is to create information mails about non-deliverable mails and send it to the original sender. The routing of mails is done based on the domain of the receiver's email address. The domains fall into these categories and need to be configured by the mail server maintainer (this means us):

- Local domains: These domains are endpoints for emails and the recipient (the part before the '<span></span>@') must have an account on the mail server machine. Account means that the user could do a regular login on the machine, not just an IMAP email account. An email with a domain of one of the local domains is routed to the 'local' output port, which puts the mail into the user's mailbox with the name before the '<span></span>@'. Local domains are configured with the parameter 'mydestination'.

- Virtual domains: These domains are endpoints for emails, but in contrast to local domains the recipient does not need to exist as an account on the mail server machine. Instead, the mail is routed to the 'lmtp' output port (at least we will configure it this way later), which delegates the mail to dovecot, which will care about placing it into the user's mailbox. Virtual domains are configured with the parameter 'virtual_mailbox_domains'.

- Relay domains: These domains do not have an endpoint on the mail server. Instead, the mail server accepts the incoming mails for the domains and tries to send the mails to another mail server. The mails for relay domains are routed to the 'smtp' output port. Relaying through this way is not part of the tutorial. The configuration parameter for relay domains is 'relay_domains'.

- Other domains not listed in one of the domains above: The mail is routed to the 'smtp' output port which will contact the mail server which is responsible for the receiver's domain and send the mail there.

The strucure of Postfix' parameter names is usually that it starts with the name of the module which is affected by the parameter, followed by a '\_', optional submodules and the actual parameter name. An example is "smtpd_sasl_tls_security_options", which addresses the "smtpd" module (the SMTP server), in this module the SASL managing part, and in this SASL manager a TLS setting named "security_options". Care must be taken to address the correct module; there are "smtp_" parameters for the SMTP client sending out mails over SMTP, and there are "smtpd_" (note the additional 'd') parameters for the SMTP server receiving incoming mails over SMTP.

Back to our configuration, which is so far still empty and no domains for routing are defined. Postfix uses these default settings:

- No virtual domains are defined ('virtual_mailbox_domains' is indirectly empty)

- The definition of local domains ('mydestination') uses some more definitions. 'mydestination' is defined as "$myhostname, localhost.$mydomain, localhost". We will soon overwrite this setting with a fixed value.

- 'myhostname' is the machine name (the fully-qualified domain name) of the mail server and is by default retrieved from the operating system. The current value of this parameter can be shown with "postconf myhostname".

- 'mydomain' is the domain name of the machine. It is set to some default value by Postfix. The current value can be shown with "postconf mydomain".

In my case, because the machine was never configured with a meaningful domain name, 'mydomain' is set to "localdomain" by default. The host name is retrieved from the OS and it can be set either by editing '/etc/hostname' (takes effect after reboot) or by calling 'hostname <new host name>'. In my case, calling 'hostname' delivers "MAILHOST", so together with the domain name the Postfix parameter 'myhostname' is "MAILHOST.localdomain". If you have a different host or domain name for your machine, your 'myhostname' parameter will look different.

With the parameters replaced with their actual values, the parameter 'mydestination' results in "MAILHOST.localdomain, localhost.localdomain, localhost". Any mail directed to one of these three domains will be placed into the local user's mailbox.

So what has happened when we sent our first test mail, from root to root? The mail was sent with the program "sendmail", which connects to Postfix through the 'sendmail' input port and sets the user - in this case "root" - as the sender. "sendmail" sends the mail to Postfix without a receiver domain, since we just called "sendmail root" and not "sendmail MAILROOT<span></span>@MAILDOMAIN".

Postfix detects the missing receiver (and sender) domain and inserts the domain from the parameter 'myorigin'. This parameter is by default set to 'myhostname'. So the mail is changed from sending "root to root" to "MAILROOT@<span></span>MAILHOST.localdomain to MAILROOT@<span></span>MAILHOST.localdomain".

The next step for Postfix is to look up where the mail should be routed to, depending on the receiver domain. Postfix notices that the (just inserted) receiver domain "MAILHOST.localdomain" is listed in the definition of 'mydestination', so it is a local domain and Postfix routes the mail to the 'local' output port. The 'local' output port looks up the recipient of the mail and detects "root" before the'<span></span>@', so it puts the mail into into "root"'s mailbox.

Before we'll do some more mailing experiments, let's change the explained parameters to values which match our needs. But it is up to you whether you want to use fixed values as described here or whether you want to use the values coming from the operating system and Postfix defaults. The new Postfix configuration 'main.cf' will be:

*/etc/postfix/main.cf*
>**mydomain = MAILDOMAIN**
**myhostname = MAILHOST.$mydomain**
**myorigin = $myhostname**
**mydestination = $myhostname**

The only local domain defined ('mydestination') here is "MAILHOST.MAILDOMAIN". This means that only mails directed to "@<span></span>MAILHOST.MAILDOMAIN" or without any domain (where Postfix will insert "@<span></span>MAILHOST.MAILDOMAIN" from 'myorigin') will be delivered to local users. Mails directed to "@<span></span>MAILDOMAIN", "@<span></span>MAILHOST" or the original "@<span></span>localdomain"/"@<span></span>MAILHOST.localdomain" do not fall into the local domains category. If you want your mail server to accept "@<span></span>MAILHOST" for local users, just add it to 'mydestination'.

Do not add "MAILDOMAIN" to 'mydestination'. Mails addressed to "@<span></span>MAILDOMAIN" should not be routed for local delivery (users who have an account on the mail server), but for virtual users with mail access through Dovecot, so this domain must not be local.

After editing 'main.cf', reload Postfix to make the changes take effect.

>`MAILROOT@MAILHOST# postfix reload`

##Some mail tests

With the new configuration, we can do some tests, when sending and receiving mails succeeds and when not. To do this, we'll simulate the SMTP sessions from the console with telnet.

An SMTP session works like this:

- The SMTP client connects to the server

- The server responds with a status code and some information ("220 MAILHOST.MAILDOMAIN ESMTP Postfix")

- The client sends information who he is ("HELO mail.remotepc.com")

- The server accepts or rejects ("250 MAILHOST.MAILDOMAIN")

- The client sends the sender of the mail ("MAIL FROM: user@<span></span>remotepc.com")

- The server accepts or rejects ("250 2.1.0 Ok")

- The client sends the receiver of the mail ("RCPT TO: MAILROOT@<span></span>MAILHOST.MAILDOMAIN")

- The server accepts or rejects ("250 2.1.5 Ok")

- The client announces the start of the mail body ("DATA")

- The server accepts or rejects ("354 End data with <CR><LF>.<CR><LF>")

- The client sends the mail body

- The server accepts or rejects the mail ("250 2.0.0 Ok: queued as 154C68D82F90")

- The client ends the conversation ("QUIT")

- The server acknowledges ("221 2.0.0 Bye") and closes the connection

We repeat the same test from above after the installation, this time with the new settings and telnet. From the mail server, call "telnet localhost 25" (the SMTP server listens on port 25) and do the following dialog. Input from you is bold. Replace 'EXTUSER@<span></span>EXTDOMAIN' with a valid mail address where you have access to; in case error mails are generated, they will be sent to this address. And although the server tells to end the mail with "<<span></span>CR<<span></span>LF>.<<span></span>CR><<span></span>LF>", you can simply finish with a single '.' on the last line.

>
`MAILROOT@MAILHOST# telnet localhost 25`
`Trying ::1...`
`Connected to localhost.localdomain.`
`Escape character is '^]'.`
`220 MAILHOST.MAILDOMAIN ESMTP Postfix`
**`HELO EXTHOST.EXTDOMAIN`**
`250 MAILHOST.MAILDOMAIN`
**`MAIL FROM: EXTUSER@EXTDOMAIN`**
`250 2.1.0 Ok`
**`RCPT TO: root`**
`250 2.1.5 Ok`
**`DATA`**
`354 End data with <CR><LF>.<CR><LF>`
**`Test B`**
**`.`**
`250 2.0.0 Ok: queued as B77948D82F90`
**`QUIT`**
`221 2.0.0 Bye`
`Connection closed by foreign host.`

When you look at your mailbox with "mutt" or "mail", you should see the new mail from EXTUSER@<span></span>EXTDOMAIN.

You can repeat the test with "RCPT TO: MAILROOT@<span></span>MAILHOST.MAILDOMAIN" instead of RCPT TO: root", and the mail will arrive, too.

Let's now try to send a mail to "MAILROOT@<span></span>MAILDOMAIN", not "MAILROOT@<span></span>MAILHOST.MAILDOMAIN":

>
`MAILROOT@MAILHOST# telnet localhost 25`
`Trying ::1...`
`Connected to localhost.localdomain.`
`Escape character is '^]'.`
`220 MAILHOST.MAILDOMAIN ESMTP Postfix`
**`HELO EXTHOST.EXTDOMAIN`**
`250 MAILHOST.MAILDOMAIN`
**`MAIL FROM: EXTUSER@EXTDOMAIN`**
`250 2.1.0 Ok`
**`RCPT TO: MAILROOT@MAILDOMAIN`**
`250 2.1.5 Ok`
**`DATA`**
`354 End data with <CR><LF>.<CR><LF>`
**`Test D`**
**`.`**
`250 2.0.0 Ok: queued as 9FACE8D82F90`
**`QUIT`**
`221 2.0.0 Bye`

This time the mail does not arrive in root's mailbox. Instead, an error message is sent to "EXTUSER@<span></span>EXTDOMAIN". The important information is "<MAILROOT@<span></span>MAILDOMAIN: mail for MAILDOMAIN loops back to myself", and this is what happens:

- Postfix accepts the mail addressed to MAILROOT@<span></span>MAILDOMAIN

- The domain "MAILDOMAIN" is not listed in one of the local, virtual or relay domain lists (only "MAILHOST.MAILDOMAIN" is configured as a local domain)

- Postfix routes the mail to the 'smtp' output port, which should send the mail to the mail server responsible for the domain "MAILDOMAIN".

- Postfix then finds out that it is itself who is responsible for "MAILDOMAIN", because it is configured so in the DNS

- It makes no sense to send the mail to itself, as he still wouldn't know where to finally put the mail

If the error mail does not arrive in the sender's mailbox, take a look at "When mail does not arrive" below. The log file could also give hints.

The next test is to send a mail to a nonexisting user:

>
`MAILROOT@MAILHOST# telnet localhost 25`
`Trying ::1...`
`Connected to localhost.localdomain.`
`Escape character is '^]'.`
`220 MAILHOST.MAILDOMAIN ESMTP Postfix`
**`HELO EXTHOST.EXTDOMAIN`**
`250 MAILHOST.MAILDOMAIN`
**`MAIL FROM: EXTUSER@EXTDOMAIN`**
`250 2.1.0 Ok`
**`RCPT TO: nouser@MAILHOST.MAILDOMAIN`**
`250 2.1.5 Ok`
**`DATA`**
`354 End data with <CR><LF>.<CR><LF>`
**`Test E`**
**`.`**
`250 2.0.0 Ok: queued as 9FACE8D82F90`
**`QUIT`**
`221 2.0.0 Bye`

Again an error message is generated and sent to "EXTUSER@<span></span>EXTDOMAIN". This time, the reason is obvious.

So far, we were sending mails from the mail server to the mail server. Next, we will send a mail from the mail server to a remote mail server:

>`MAILROOT@MAILHOST# telnet localhost 25`
`Trying ::1...`
`Connected to localhost.localdomain.`
`Escape character is '^]'.`
`220 MAILHOST.MAILDOMAIN ESMTP Postfix`
**`HELO EXTHOST.EXTDOMAIN`**
`250 MAILHOST.MAILDOMAIN`
**`MAIL FROM: root`**
`250 2.1.0 Ok`
**`RCPT TO: EXTUSER@EXTDOMAIN`**
`250 2.1.5 Ok`
**`DATA`**
`354 End data with <CR><LF>.<CR><LF>`
**`Test F`**
**`.`**
`250 2.0.0 Ok: queued as 441818D82F90`
**`QUIT`**
`221 2.0.0 Bye`
`Connection closed by foreign host.`

This test mail should arrive in "EXTUSER@<span></span>EXTDOMAIN"'s mailbox. Again, if this is not the case, take a look at the logs and "When mail does not arrive" below.

In the next test, we will do the reverse and send a mail from outside to the mail server. For this, start the telnet session from a different machine, not the mail server:

>
`EXTUSER@EXTHOST$ telnet MAILDOMAIN 25`
`Trying MAILIP...`
`Connected to MAILDOMAIN.`
`Escape character is '^]'.`
`220 MAILHOST.MAILDOMAIN ESMTP Postfix`
**`HELO EXTDOMAIN`**
`250 MAILHOST.MAILDOMAIN`
**`MAIL FROM: EXTUSER@EXTDOMAIN`**
`250 2.1.0 Ok`
**`RCPT TO: root`**
`250 2.1.5 Ok`
**`DATA`**
`354 End data with <CR><LF>.<CR><LF>`
**`Test G`**
**`.`**
`250 2.0.0 Ok: queued as 4C7678D82F90`
**`QUIT`**
`221 2.0.0 Bye`
`Connection closed by foreign host.`

This mail should arrive in root's mailbox.

The last test is to send a mail from outside to any other mail server on the internet. This represents the case when you want to send an email from a different machine (the computer you are working on in the office, not the mail server, or from your home office) over the new mail server to any recipient in the world. In this example, we will send a mail from "EXTDOMAIN" to "EXTDOMAIN", using the new mail server:

>
`EXTUSER@EXTHOST$ telnet MAILDOMAIN 25`
`Trying MAILIP...`
`Connected to MAILDOMAIN.`
`Escape character is '^]'.`
`220 MAILHOST.MAILDOMAIN ESMTP Postfix`
**`HELO EXTDOMAIN`**
`250 MAILHOST.MAILDOMAIN`
**`MAIL FROM: EXTUSER@EXTDOMAIN`**
`250 2.1.0 Ok`
**`RCPT TO: EXTUSER@EXTDOMAIN`**
`554 5.7.1 <EXTUSER@EXTDOMAIN>: Relay access denied`

This test failed, the mail server does not accept the mail. The reason is that your mail server has nothing to do with neither the sender nor the receiver domain "EXTHOST.EXTDOMAIN". Changing "MAIL FROM: EXTUSER@<span></span>EXTDOMAIN" to "MAIL FROM: MAILROOT@<span></span>MAILHOST.MAILDOMAIN" doesn't help either, as everybody could claim he is "MAILROOT@<span></span>MAILHOST.MAILDOMAIN". This behaviour prevents spammers or other people from using the mail server for sending mails you have nothing to do with. If the server would accept all mails to all recipients, it would be a so called "open relay", would soon be used by spammers for sending masses of spam mails, and the server would then soon be blocked. So by default, Postfix does not accept the mail in this test.

But why was Postfix accepting the mail when we did the same test, and just made the telnet connection from the mail server? This is controlled by the Postfix parameter 'mynetworks'. This parameter contains a list of IP addresses or address ranges which can be trusted, and from which Postfix accepts mails for sending anywhere. By default, this contains the IP addresses associated with the mail server, i.e. the 'localhost' IP address and the public IP address. If you set 'mynetworks' empty, Postfix will not accept mails to the outside, even when coming from the same machine. For now (and throughout this tutorial) we leave 'mynetworks' at the default value.

This behaviour may prevent people from abusing the mail server, but it also prevents us from sending legitimate mail through the server, and this is not what we want. We come back later how to deal with this problem. So far we can't send mail from a different machine to the outside world.

##Dovecot as IMAP server

The default configuration files of Dovecot contain a confusing number of settings, and even more settings are loaded with the 'include' directive, leaving you a little helpless at the start. But like with Postfix, we can leave Dovecot at the internal default settings and start with an empty configuration file with no further includes.

Later, when you get more familiar with Dovecot, you can switch back to the original default setting files, if you want to.

##Dovecot preparation

After installing Dovecot, we need to do some preparations before we start with the tests with Dovecot.

First of all, there is no location where user mailboxes are stored yet. We create a base directory 'vmail' which stands for virtual mailboxes. Virtual because the users therein have no regular user account on the machine, just the mail account.

>`MAILROOT@MAILHOST# mkdir /var/vmail`

For the regular work, Dovecot requires several user accounts for security reasons. Though a 'dovecot' user was created during the installation, we need another user for mailbox access. This account is not created automatically, because there is more than one way how to access the mailboxes, and not necessarily with this required account. We give this new user the name 'vmail' and create a group 'vmail' as well. The name is not related to the mailboxes base directory '/var/vmail', it could be any other name (the user must not exist yet, of course).

>
`MAILROOT@MAILHOST# groupadd vmail`
`MAILROOT@MAILHOST# useradd vmail -g vmail`

And we transfer the mailboxes directory to the new user:

>`MAILROOT@MAILHOST# chown vmail:vmail /var/vmail`

Like with Postfix, we start configuring Dovecot with an empty configuration file and take a look what happens or what Dovecot offers:

>
`MAILROOT@MAILHOST# mv /etc/dovecot.conf /etc/dovecot.conf.bak`
`MAILROOT@MAILHOST# >/etc/dovecot.conf`
`MAILROOT@MAILHOST# service dovecot start`

The main purpose of Dovecot is to act as an IMAP server for mailbox access. The standard IMAP ports are 143 and 993, so we expect them to appear as listening for incoming connections. But when we look at the open ports with

>`MAILROOT@MAILHOST# netstat -nat`

neither port 143 nor port 993 are listed as listening, which means Dovecot is not offering an IMAP service so far.

The IMAP server has to be enabled in Dovecot first, so we change the '/etc/dovecot.conf' to:

*/etc/dovecot/dovecot.conf*
>**protocols = imap**

and restart Dovecot:

>`MAILROOT@MAILHOST# service dovecot restart`

When we look at the open ports again, ports 143 and 993 now appear. As with Postfix, we will simulate an IMAP client with a telnet session:

>
`MAILROOT@MAILHOST# telnet localhost 431`
`Trying 127.0.0.1...`
`Connected to localhost.`
`Escape character is '^]'.`
`Connection closed by foreign host.`

The connection is immediately terminated by Dovecot, and when we take a look at the log ('/var/log/syslog'), the error is abouth something with SSL. But for the first steps, we don't want to use SSL/TLS. So this needs to be configured:

*/etc/dovecot/dovecot.conf*
>protocols = imap
**ssl = no**

>`MAILROOT@MAILHOST# service dovecot restart`

Next try:

>
`MAILROOT@MAILHOST# telnet localhost 143`
`Trying 127.0.0.1...`
`Connected to localhost.`
`Escape character is '^]'.`
`* BYE Disconnected: Auth process broken`
`Connection closed by foreign host.`

Still not working, the logs give the answer: "No passdbs specified in configuration file. PLAIN mechanism needs one"

This means there is no password database configured. Right, we didn't tell where the database with users and their passwords can be found, and we even didn't create one yet. So let's create such a database.

Dovecot offers several possibilities where user and password information can be stored. It could be a simple text file, a SQL database, or something else. We will use a text file. Those files supportes by Dovecot have a structure similar to the '/etc/passwd' file of Linux. Basically, it contains a user name and a password, seperated by ':'. Like 'etc/passwd', it can contain some more information, but this is only needed for scenarios outside the scope of this tutorial. We place the database file in '/etc/dovecot/users.db' (with the suffix '.db' at your own choice), so create the file and insert:

*/etc/dovecot/users.db*
>**MAILUSER@<span></span>MAILDOMAIN:123456**

The login name for the first mail user is "MAILUSER@<span></span>MAILDOMAIN", and his password is "123456".

The user needs to login with his name including the domain because we want to be future-proof. In case at some time later in the future we do not only want to handle mail for the domain "MAILDOMAIN", but also for e.g. "next-MAILDOMAIN", the mailboxes from both domains should be managed seperately. And if the user "MAILUSER" logs in, which mailbox should be presented, the one from "MAILDOMAIN" or the one from "next-MAILDOMAIN"? That's why the domain gets part of the user name. If you really want and you know you will never have more than one domain, you can configure login names without the domain.

It is bad style to keep the password as plain text, as we do here. We will later change this. The reason is that if someone captures the password database file, he has direct access to the user passwords. It is better to keep the passwords encrypted (hashed) in the file, so that the passwords are not presented ready to be used to the attacker.

We can now connect the password file to Dovecot. Edit the Dovecot configuration:

*/etc/dovecot/dovecot.conf*
>protocols = imap
ssl = no
**passdb {**
**driver = passwd-file**
**args = scheme=PLAIN /etc/dovecot/users.db**
**}**

>`MAILROOT@MAILHOST# service dovecot restart`

'driver' determines which service should be used to verify a user password. 'passwd-file' is the service which checks the entered password to the password in a password file. If the password was stored in a SQL database, a different driver would be used here. The 'driver' service simply returns whether the given user/password combination was correct or not.

'args' are the arguments which are passed to the driver. In this case this is the location of the password file ("/etc/dovecot/users.db") and how the password is encrypted ("scheme=PLAIN").

When we start an IMAP telnet session, we get:

>
`MAILROOT@MAILHOST# telnet localhost 143`
`Trying 127.0.0.1...`
`Connected to localhost.`
`Escape character is '^]'.`
`* OK [CAPABILITY IMAP4rev1 LITERAL+ SASL-IR LOGIN-REFERRALS ID ENABLE IDLE AUTH=PLAIN] Dovecot (Ubuntu) ready.`

That looks better than before, the IMAP server is waiting for input and we try to log in:

>
**`a LOGIN MAILUSER@MAILDOMAIN 123456`**
`* BYE Internal error occurred. Refer to server log for more information.`
`Connection closed by foreign host.`

The single 'a' before the "LOGIN" is a transaction token. Each command you give to an IMAP server must be preceeded by such a token. Server responses are preceeded by the token of the request, so that it can be determined to which request a server response belongs. For the simple test we are doing here you can always take the same token, or even '.'.

Our login attempt fails, and the logs tell "Error: user MAILUSER@<span></span>MAILDOMAIN: Couldn't drop privileges: User is missing UID (see mail_uid setting)". In other words this means: Dovecot wanted to access 'MAILUSER's mailbox as a different user, the user for mailbox accesses, but he didn't know as which user he should do it. Above, we created the user 'vmail' for this purpose, but so far Dovecot doesn't know about this user and that he should use it. Insert it into the configuration:

*/etc/dovecot/dovecot.conf*
>protocols = imap
ssl = no
passdb {
  driver = passwd-file
  args = scheme=PLAIN /etc/dovecot/users.db
}
**mail_gid = vmail**
**mail_uid = vmail**

>`MAILROOT@MAILHOST# service dovecot restart`

And the next try to log in:

>
`MAILROOT@MAILHOST# telnet localhost 143`
`Trying 127.0.0.1...`
`Connected to localhost.`
`Escape character is '^]'.`
`* OK [CAPABILITY IMAP4rev1 LITERAL+ SASL-IR LOGIN-REFERRALS ID ENABLE IDLE AUTH=PLAIN] Dovecot (Ubuntu) ready.`
**`a LOGIN MAILUSER@MAILDOMAIN 123456`**
`* BYE Internal error occurred. Refer to server log for more information.`
`Connection closed by foreign host.`

Still no login possible, the log says "Error: user MAILUSER@<span></span>MAILDOMAIN: Initialization failed: mail_location not set and autodetection failed: Mail storage autodetection failed with home=(not set)"

This means, Dovecot does not know where to look for 'MAILUSER's mailbox. Above, we created a directory for the user mailboxes, but didn't tell Dovecot about it. This is done with the parameters 'mail_home' and 'mail_location'.

'mail_home' is a pattern for the base directory of each user, like the home directory for a Linux user. The pattern may (and always will) contain placeholders for the user name and the domain. The most useful variables are:

- '%u' is the complete user name, in our case 'MAILUSER@<span></span>MAILDOMAIN'
- '%d' is the domain part of the user name 'MAILDOMAIN'
- '%n' is the name part of the user name 'MAILUSER'

There are some more variables, described in http://wiki2.dovecot.org/Variables

In our created base mail directory, we want to have the domains separate, and in each domain a separate user home directory. So we construct the parameter 'mail_home' to "/var/vmail/%d/%n".

'mail_location' defines where and how to store mails. This parameter consists of two or three parts separated by ':'.

The first part is the format how mails are stored. Two common formats are 'mbox', where all mails are kept in one single file, and 'maildir', where each mail is kept in one file. Dovecot offers some more formats, as described in http://wiki2.dovecot.org/MailboxFormat. We choose one mail per file, 'maildir'.

The second part defines the location for storing mails, in other words the base directory for the user's mailboxes. The user can have several mailboxes, which are represented in mail clients as folders. The location must be an absolute path, but '~' can be used as the user's home directory. And the mailboxes should not be stored directly in the home directory, as other files can appear there and would then falsely be shown as mailboxes. For our mailboxes, we choose the path "~/mail".

The third part of 'mail_location' contains some optional parameters. The parameters are described in http://wiki2.dovecot.org/MailLocation, multiple parameters are seperated by ':'. We do not set one of the parameters.

The resulting value for 'mail_location' is thus "maildir:~/mail".

The new Dovecot configuration file looks like this:

*/etc/dovecot/dovecot.conf*
>protocols = imap
ssl = no
passdb {
  driver = passwd-file
  args = scheme=PLAIN /etc/dovecot/users.db
}
mail_gid = vmail
mail_uid = vmail
**mail_home = /var/vmail/%d/%n**
**mail_location = maildir:~/mail**

>`MAILROOT@MAILHOST# service dovecot restart`

And we try to login via telnet again:

>
`MAILROOT@MAILHOST# telnet localhost 143`
`Trying 127.0.0.1...`
`Connected to localhost.`
`Escape character is '^]'.`
`* OK [CAPABILITY IMAP4rev1 LITERAL+ SASL-IR LOGIN-REFERRALS ID ENABLE IDLE AUTH=PLAIN] Dovecot (Ubuntu) ready.`
**`a LOGIN MAILUSER@MAILDOMAIN 123456`**
`a OK [CAPABILITY IMAP4rev1 LITERAL+ SASL-IR LOGIN-REFERRALS ID ENABLE IDLE SORT SORT=DISPLAY THREAD=REFERENCES THREAD=REFS THREAD=ORDEREDSUBJECT MULTIAPPEND URL-PARTIAL CATENATE UNSELECT CHILDREN NAMESPACE UIDPLUS LIST-EXTENDED I18NLEVEL=1 CONDSTORE QRESYNC ESEARCH ESORT SEARCHRES WITHIN CONTEXT=SEARCH LIST-STATUS SPECIAL-USE BINARY MOVE] Logged in`

This time the login was successful. Dovecot is now waiting to receive some commands. We let us give a list of the user's folders:

>
**`a list "" "*"`**
`* LIST (\HasNoChildren) "." INBOX`
`a OK List completed.`

Dovecot tells us that user "MAILUSER@<span></span>MAILDOMAIN" has the mailbox "INBOX". We quit the IMAP session.

>
**`a logout`**
`* BYE Logging out`
`a OK Logout completed.`
`Connection closed by foreign host.`

Let's take a look at the file system, what has happened since we created the base mail directory '/var/vmail':

>
`MAILROOT@MAILHOST# find /var/vmail`
`/var/vmail/`
`/var/vmail/MAILDOMAIN`
`/var/vmail/MAILDOMAIN/MAILUSER`
`/var/vmail/MAILDOMAIN/MAILUSER/mail`

A directory for the domain "MAILDOMAIN", for the user "MAILUSER" and for the mailboxes "mail" have been created.

By now we have tested the IMAP access locally from the mail server. We should try if the access from the internet does work as well. Go to your remote machine on the internet and from there log in to the IMAP server:

>
`EXTUSER@EXTHOST# telnet MAILHOST.MAILDOMAIN 143`
`Trying MAILIP...`
`Connected to MAILHOST.MAILDOMAIN.`
`Escape character is '^]'.`
`* OK [CAPABILITY IMAP4rev1 LITERAL+ SASL-IR LOGIN-REFERRALS ID ENABLE IDLE LOGINDISABLED] Dovecot (Ubuntu) ready.`
**`a login MAILUSER@MAILDOMAIN 123456`**
`* BAD [ALERT] Plaintext authentication not allowed without SSL/TLS, but your client did it anyway. If anyone was listening, the password was exposed.`
`a NO [PRIVACYREQUIRED] Plaintext authentication disallowed on non-secure (SSL/TLS) connections.`

It seems like we have the same behaviour as we had with Postfix. Logins from the local machine are allowed, remote logins not. The error message tells what the problem is. For our tests, we need to allow those totally insecure logins. Later, we will make it safe. The parameter to allow the login is 'disable_plaintext_auth', and it forbids (or allows) plain text logins over insecure connections. Edit the Dovecot configuration:

*/etc/dovecot/dovecot.conf*
>protocols = imap
ssl = no
passdb {
  driver = passwd-file
  args = scheme=PLAIN /etc/dovecot/users.db
}
mail_gid = vmail
mail_uid = vmail
mail_home = /var/vmail/%d/%n
mail_location = maildir:~/mail
**disable_plaintext_auth = no**

>`MAILROOT@MAILHOST# service dovecot restart`

>
`EXTUSER@EXTHOST# telnet MAILHOST.MAILDOMAIN 143`
`Trying MAILIP...`
`Connected to MAILHOST.MAILDOMAIN.`
`Escape character is '^]'.`
`* OK [CAPABILITY IMAP4rev1 LITERAL+ SASL-IR LOGIN-REFERRALS ID ENABLE IDLE AUTH=PLAIN] Dovecot (Ubuntu) ready.`
**`a login MAILUSER@MAILDOMAIN 123456`**
`a OK [CAPABILITY IMAP4rev1 LITERAL+ SASL-IR LOGIN-REFERRALS ID ENABLE IDLE SORT SORT=DISPLAY THREAD=REFERENCES THREAD=REFS THREAD=ORDEREDSUBJECT MULTIAPPEND URL-PARTIAL CATENATE UNSELECT CHILDREN NAMESPACE UIDPLUS LIST-EXTENDED I18NLEVEL=1 CONDSTORE QRESYNC ESEARCH ESORT SEARCHRES WITHIN CONTEXT=SEARCH LIST-STATUS SPECIAL-USE BINARY MOVE] Logged in`
**`a logout`**
`* BYE Logging out`
`a OK Logout completed.`
`Connection closed by foreign host.`

Now the login works.

We can now move away from telnet and configure a real mail client like Thunderbird. In your mail client, create a new mail account and configure it with these settings:

- Server type: IMAP

- Server name: MAILDOMAIN

- Server port: 143

- User name: MAILUSER@<span></span>MAILDOMAIN (this is the name we used during the telnet "a login MAILUSER@<span></span>MAILDOMAIN 123456")

- Connection security: None

- Authentication method: Password

It may be asked for the configuration of the outgoing server, but these settings are not important (at least for now).

When finished, try to connect to the server with your new account. A password dialog should appear and the login should be successful. At least an "Inbox" folder should be visible.

When Thunderbird is used, a "Trash" folder is also created, and with "find /var/vmail", you can see that some files were created in the user's 'mail' directory. The "Trash" folder can be found in 'mail/.Trash' (notice it is a hidden directory starting with '.')

##Encryption and authentication in Dovecot and Postfix

There are a number of confusing terms related to email when it comes to authentication and encryption. In your mail client you will see something like "TLS", "STARTTLS", "Kerberos", "Unencrypted password", "SASL" and so on, and you were happy when the mail client picked or guessed the right default values, or when you were told what the settings are, without knowing what they mean. Now you will need to understand what they mean, but it is really quite simple.

The one thing is the user authentication. Access to user mail accounts should only be granted after the user has successfully authenticated to the mail server. And for outgoing mails, the user needs to authenticate that he is allowed to send mails to the outer world and that he is not someone who wants to abuse the mail server. The other thing, and totally independent from the user authentication, is the encryption of data transferred between client and mail server.

The encryption part is virtually always TLS/SSL (or even not just virtually). TLS is the successor of the former SSL and is best known from HTTPS. After a client connects to a server, the first thing that both sides are doing is to setup an encryption layer, which encrypts all data going through that connection, from the beginning on, before any user data are transferred.

With mail servers, there exists a variant of TLS, which is named "STARTTLS". STARTTLS is also TLS encryption, with the difference that TLS encryption is started later in the session, after a specific request. After the client connects to the server, the communication between both is unencrypted. Later, after some communication has been done, a request to switch to TLS is sent over the line, then the TLS handshake begins and all subsequent communication is encrypted.

A third "encryption type" is no encryption at all.

The advantage of STARTTLS is that TLS can be enabled optionally, the communication can be done either unencrypted or encrypted. The client always connects to one specific TCP port, starts with unencrypted communication and can switch to encrypted later. In contrast, for HTTP requests it must be known in advance whether the transfer should be unencrypted HTTP - the client needs to connect to port 80 - or whether it should be encrypted HTTPS, where the client needs to connect to port 443. With STARTTLS, both unencrypted and encrypted connections can be handled over a single TCP port.

For the user authentication, there are a number of choices. The simplest method is that the connecting user gives a user name and a password, and the server checks if the password is correct. Because this method is sufficient for our small server, the other methods are not explained here. Password authentication can be done either unencrypted or encrypted, independant of the connection encryption. This means the connection can be set to unencrypted (no TLS) and the password authentication - and only the authentication - can be set to encrypted. In our mail server, we will always use TLS connection encryption. This means we can set password authentication to unencrypted, because the unencrypted password will be encrypted in the TLS connection encryption layer.

The term "SASL" denotes the mechanism how the authentication is performed.

In the next step, we will secure the data transmission between the user and Dovecot by enabling TLS. For TLS, the server needs a private key and a certificate containing the public key. Fortunately, during the installation of Dovecot a self signed certificate was generated and can simply be used by us. Later, you can replace this certificate with an official certificate. The certificate and key can be found in '/etc/dovecot/dovecot.pem' and '/etc/dovecot/private/dovecot.pem'.

We are changing the parameter 'ssl' from "no" to "required". This means that only encrypted connections are allowed. It is also possible to set the value to "yes", which means that encrypted connections are supported but they are not mandatory, but we want all communication to be encrypted.

The parameter 'disable_plaintext_auth' is not required any more, as the whole communication is now encrypted. Also note that the original line "ssl = no" gets disabled.

Adjust the configuration file:

*/etc/dovecot/dovecot.conf*
>protocols = imap
**\#**ssl = no
passdb {
  driver = passwd-file
  args = scheme=PLAIN /etc/dovecot/users.db
}
mail_gid = vmail
mail_uid = vmail
mail_home = /var/vmail/%d/%n
mail_location = maildir:~/mail
**\#**disable_plaintext_auth = no
**ssl = required**
**ssl_cert = </etc/dovecot/dovecot.pem**
**ssl_key = </etc/dovecot/private/dovecot.pem**

The parameters 'ssl_cert' and 'ssl_key' don't expect file names but the actual content of the files. The '<' does care about this, it reads the content from the given files.

>`MAILROOT@MAILHOST# service dovecot restart`

When you now connect with your mail client to the server (or by activating "Get new messages"), you will get an error. This is correct, because the mail client is still configured for unencrypted connections.

Change the account settings to use "STARTTLS" for the encryption and try to connect again. You will probably get a warning about the self signed certificate. Accept it and allow an exception for this certificate. From now on, you won't get an error message from your mail client any more. But there is not much to see yet, the mailbox ist still empty.

Dovecot not only offers STARTTLS as encryption, but also pure TLS. This works as follows: On port 143, the unencrypted IMAP communication is offered. When a client connects to this port, the communication starts unencrypted, but it can be switched to TLS with the STARTTLS mechanism. This switch has to be performed before the login.

Beside port 143, Dovecot opens a second port on number 993, where it waits for TLS encrypted connections. Here, the communication is encrypted from the very start and no STARTTLS switch is required. Both ports are working completely independant of each other, that means when a STARTTLS wants to switch to encryption, this happens on the same connection and there is no new encrypted connection to port 993.

For your mail client configuration this means that either you need to choose STARTTLS as encryption together with port 143, or you choose TLS/SSL as encryption together with port 993. TLS won't work on port 143, and STARTTLS won't work on port 993. Disabled encryption won't work on both ports, we have just disabled it.

##Configure virtual domains in Postfix

Earlier it was explained that in Postfix, mails for domains listed in 'mydestinations' are routed to the 'local' output, and mails for domains listed in 'virtual_mailbox_domains' are routed to the 'lmtp' output port. This mechanism is explained in more detail here, because it helps to understand the whole picture.

When a mail arrives, Postfix looks up where this domain is assigned to, that means whether it is listed in 'mydestinations' or in 'virtual_mailbox_domains'; it is also possible the destination domain is not listed at all. When Postfix has found the corresponding entry, it looks up which service is responsible for the transportation, or in other words what service the mail should be sent to. If the destination domain is listed in the 'mydestinations' parameter, Postfix uses the parameter 'local_transport' to look up the name of the service which is responsible for the further transport of the mail. If the destination domain is listed in 'virtual_mailbox_domains', the mail will be transported by the service whose name is configured in the parameter 'virtual_transport'.

These services are just symbolic names. The default name in 'local_transport' is "local", and "virtual" in 'virtual_transport'. The link to real programs that act on the mails happens in the file '/etc/postfix/master.cf'. There you will find a list of services, and beside some parameters each service has a program assigned, which is run on the mail.

So when a mail for '@<span></span>MAILDOMAIN' arrives, and 'MAILDOMAIN' is listed in 'virtual_mailbox_domains', Postfix looks up the content of 'virtual_transport', which is "virtual". Next, Postfix takes a look at the table in '/etc/postfix/master.cf' at the entry for "virtual". It then finds that the program "virtual" should be run, which eventually handles the mail. In this case, the command "virtual" is run without arguments, but other entries in 'master.cf' show examples of more complex calls.

We want to achieve that incoming mails for our virtual domain "MAILDOMAIN" get somehow transported to Dovecot, which handles putting the mail into the user mailboxes. One solution is to do this through LMTP, the Local Mail Transport Protocol, a protocol similar to SMTP with focus on local delivery. Dovecot contains a LMTP server, so we need to make Postfix send incoming mails for virtual domains to the LMTP server of Dovecot. This is simply done by setting the transport service for virtual domains to use Postfix' LMPT client, and not the default "virtual" service any more. In other words, we just need to configure the parameter 'virtual_transport' with the LMTP service. So we set 'virtual_transport' to the service "lmtp" and configure a service "lmtp" in '/etc/postfix/master.cf'. Fortunately, a service "lmtp" is already configured in master.cf, ready to be used, so actually we don't need to edit this configuration file.

The Postfix LMTP client can connect to the Dovecot server with a TCP network connection, or because Postfix and Dovecot are running on the same machine, through a UNIX-domain socket. The latter is the preferred method, as it gives more security. The parameter 'virtual_transport' is made up of the service name "lmtp", the access method "unix" for UNIX-domain sockets ("inet" for TCP connections), and "private/dovecot-lmtp" is the name of the socket including the path.

We also configure the list of virtual domains, which by now contains only one domain, "MAILDOMAIN". Here is the new configuration:

*/etc/postfix/main.cf*
>mydomain = MAILDOMAIN
myhostname = MAILHOST.$mydomain
myorigin = $myhostname
mydestination = $myhostname
**virtual_mailbox_domains = MAILDOMAIN**
**virtual_transport = lmtp:unix:private/dovecot-lmtp**

>`MAILROOT@MAILHOST# postfix reload`

We will send a test mail from the external host to the newly configured virtual domain:

>
`EXTUSER@EXTHOST$ telnet MAILHOST.MAILDOMAIN 25`
`Trying MAILIP...`
`Connected to MAILIP.`
`Escape character is '^]'.`
`220 MAILHOST.MAILDOMAIN ESMTP Postfix`
**`HELO EXTHOST.EXTDOMAIN`**
`250 MAILHOST.MAILDOMAIN`
**`MAIL FROM: EXTUSER@EXTDOMAIN`**
`250 2.1.0 Ok`
**`RCPT TO: MAILUSER@MAILDOMAIN`**
`250 2.1.5 Ok`
**`DATA`**
`354 End data with <CR><LF>.<CR><LF>`
**`Test H`**
**`.`**
`250 2.0.0 Ok: queued as 5AFCDE42E9`
**`QUIT`**
`221 2.0.0 Bye`
`Connection closed by foreign host.`

The server accepted the mail. But a look at the logs ('/var/log/syslog') shows that the mail cannot be delivered to Dovecot, because the socket 'private/dovecot-lmtp' does not exist. This is correct, as we haven't configured Dovecot to act as a LMTP server yet. At least we see that Postfix has detected the domain 'MAILDOMAIN' as a virtual domain and tries to deliver the mail into the correct direction.

So we need to make Dovecot accept incoming mails through LMTP. Therefore, the parameter 'protocols' is added with 'lmtp', which enables the LMTP server. The section starting with "service lmtp {" contains the parameters for the protocol, which is pretty self-explaining. The location of the UNIX-domain socket is set together with its permissions.

*/etc/dovecot/dovecot.conf*
>protocols = imap lmtp
passdb {
  driver = passwd-file
  args = scheme=PLAIN /etc/dovecot/users.db
}
mail_gid = vmail
mail_uid = vmail
mail_home = /var/vmail/%d/%n
mail_location = maildir:~/mail
ssl = required
ssl_cert = </etc/dovecot/dovecot.pem
ssl_key = </etc/dovecot/private/dovecot.pem
**service lmtp {**
**unix_listener /var/spool/postfix/private/dovecot-lmtp {**
**user = postfix**
**group = postfix**
**mode = 0600**
**}**
**}**

>`MAILROOT@MAILHOST# service dovecot restart`

You can now send a new mail and see what happens, or you can also just wait, because the last mail is still queued in Postfix and it will do delivery attempts from time to time. If you want to wait, you can 'tail -f /var/log/syslog' and you get noticed when something happens. But it's easier to simply create a new test mail.

In either case, we need to look at the logs and find out that the mail could not be delivered yet. The error is "postmaster_address setting not given". It is possible that Dovecot needs to create bounce mails, and these have to be filled out with a sender. The parameter 'postmaster_address' should contain the sender.

And before we see the next error: Also for bounce mails the host name needs to be configured in the parameter 'hostname'. The modified configuration:

*/etc/dovecot/dovecot.conf*
>protocols = imap lmtp
passdb {
  driver = passwd-file
  args = scheme=PLAIN /etc/dovecot/users.db
}
mail_gid = vmail
mail_uid = vmail
mail_home = /var/vmail/%d/%n
mail_location = maildir:~/mail
ssl = required
ssl_cert = </etc/dovecot/dovecot.pem
ssl_key = </etc/dovecot/private/dovecot.pem
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    user = postfix
    group = postfix
    mode = 0600
  }
}
**postmaster_address = postmaster @MAILDOMAIN **
**hostname = MAILHOST**

__*Remove the space between "postmaster" and @<span></span>MAILDOMAIN, it's only here for formatting reasons*__

>`MAILROOT@MAILHOST# service dovecot restart`

When sending a new mail now (this time not displayed here) and looking at the logs, the mail could be delivered. And when we update our mail client to load new messages, the message is shown.

Receiving emails from the internet, delivering it into virtual Dovecot mailboxes and user access to the mailboxes is now generally working.

We should not forget to store the user passwords encrypted, that when an attacker gets access to the user password database, the encrypted passwords are worthless for him. We do this now.

To create an encrypted password, we use the program 'doveadm', which gives administration access to Dovecot, and one part of it is the encryption of passwords. Run the program and enter our password "123456" twice:

>
`MAILROOT@MAILHOST# doveadm pw -s SHA512-CRYPT`
`Enter new password: 123456`
`Retype new password: 123456`
`{SHA512-CRYPT}$6$g6adDoglZXU5CJq1$AMojgOJQPtdEEGt1MW86YZUDMlf1Wi6QLz6RH.7BHJpNzjQmYpRmP./IN0eRP8.eLAmEcnoRtzrS1jonKQT9k/`

You will probably get a different result, as the checksum is salted.

As you can guess, "SHA512-CRYPT" stands for a SHA512 encryption. Other encryption methods are "BLF-CRYPT" for Blowfish, "SHA256-CRYPT" for SHA256 and "MD5-CRYPT" for the old MD5, which should not be used any more. See http://wiki2.dovecot.org/Authentication/PasswordSchemes.

In the user passwords database '/etc/dovecot/users.db', replace the plain text password "123456" with the newly created password, but without the "{SHA512-CRYPT}" part, so that the user database looks like:

*/etc/dovecot/users.db*
>MAILUSER@<span></span>MAILDOMAIN:$6$g6adDoglZXU5CJq1$AMojgOJQPtdEEGt1MW86YZUDMlf1Wi6QLz6RH.7BHJpNzjQmYpRmP./IN0eRP8.eLAmEcnoRtzrS1jonKQT9k/

Additionally, Dovecot needs to be told that the passwords are not plain text anymore, but are SHA512 encrypted, so change Dovecot's configuration to:

*/etc/dovecot/dovecot.conf*
>protocols = imap lmtp
passdb {
driver = passwd-file
**\#**  args = scheme=PLAIN /etc/dovecot/users.db
**args = scheme=SHA512-CRYPT /etc/dovecot/users.db**
}
mail_gid = vmail
mail_uid = vmail
mail_home = /var/vmail/%d/%n
mail_location = maildir:~/mail
ssl = required
ssl_cert = </etc/dovecot/dovecot.pem
ssl_key = </etc/dovecot/private/dovecot.pem
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    user = postfix
    group = postfix
    mode = 0600
  }
}
postmaster_address = postmaster @MAILDOMAIN
hostname = MAILHOST

>`MAILROOT@MAILHOST# service dovecot restart`

When you now try to connect to 'MAILUSER's mailbox and enter the password "123456", which hasn't changed but it is only stored encrypted, the login should still be successful. 

##Sending emails

What remains is sending emails from any computer to any address. Though the mail client user has the impression that mails are sent somehow through the mailbox and thus Dovecot, in fact this is not the case and the mail client contacts Postfix directly like we did with our telnet sessions. The problem is that mail from outside of the mail server's network going to somewhere outside is still not allowed. To deal with this problem, we can add a kind of exception to Postfix, that when the sender can authenticate as a valid user, the mail is accepted.

Postfix does not have a builtin authentication environment, but can be configured to let Dovecot do the authentication. When the user wants to send a mail, Postfix asks for a user name and password, passes them to Dovecot, Dovecot tells Postfix whether this is a valid user or not and Postfix accepts the mail. This also has the advantage that only one user database has to be maintained, the one in Dovecot.

The authentication mechanism is called 'SASL'. And because the authentication is done when the mail is delivered to Postfix' SMTP server, the configuration variable names start with 'smtpd_sasl_'.

With the parameter 'smtpd_sasl_auth_enable', SASL gets enabled. Parameter 'smtpd_sasl_type' configures how Postfix should do the authentication. Postfix not only can use Dovecot for the authentication, but other programs too, and this parameter selects the authentication helper, which in this case is "dovecot". As in the LMTP configuration, the communication between Postfix and Dovecot during the authentication runs over a UNIX-domain socket. The name of the socket is configured in 'smtpd_sasl_path'. Edit the Postfix configuration:

*/etc/postfix/main.cf*
>mydomain = MAILDOMAIN
myhostname = postfix.$mydomain
myorigin = $myhostname
mydestination = $myhostname
virtual_mailbox_domains = MAILDOMAIN
virtual_transport = lmtp:unix:private/dovecot-lmtp
**smtpd_sasl_auth_enable = yes**
**smtpd_sasl_type = dovecot**
**smtpd_sasl_path = private/auth**

>`MAILROOT@MAILHOST# postfix reload`

The counterpart - Dovecot - needs to be configured to work with Postfix, too. At least it needs to know the name of the socket where Dovecot should wait for authentication request from Postfix. And this actually the only extension to Dovecot's configuration file:

*/etc/dovecot/dovecot.conf*
>protocols = imap lmtp
passdb {
  driver = passwd-file
  args = scheme=PLAIN /etc/dovecot/users.db
}
mail_gid = vmail
mail_uid = vmail
mail_home = /var/vmail/%d/%n
mail_location = maildir:~/mail
ssl = required
ssl_cert = </etc/dovecot/dovecot.pem
ssl_key = </etc/dovecot/private/dovecot.pem
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    user = postfix
    group = postfix
    mode = 0600
  }
}
postmaster_address = postmaster @MAILDOMAIN
hostname = MAILHOST
**service auth {**
**unix_listener /var/spool/postfix/private/auth {**
**user = postfix**
**group = postfix**
**mode = 0600**
**}**
**}**

>`MAILROOT@MAILHOST# service dovecot restart`

Before we can test if the mail server now accepts mails from outside to outside, the mail client's outgoing server needs to be configured correctly. The settings should be:

- Server name: MAILDOMAIN

- Server port: 25

- Security: none

- Authentication: Unencrypted password

- User name: MAILUSER@<span></span>MAILDOMAIN

Now write a mail as user "MAILUSER" in your mail client and send it to any valid address, where you have access to. Do not send it to "@<span></span>MAILDOMAIN", as we want to check if sending to the outer world works, and "@<span></span>MAILDOMAIN" is managed by Postfix and not outside. The mail client will ask for the password, and the mail should then arrive at the given destination.

Now we have the situation that the user password is transferred totally unencrypted from the mail client over the internet to Postfix. So we want to enable TLS in Postfix. When the connection from mail client to mail server is encrypted, the password does not need any further encryption.

Beside enabling TLS in Postfix, as in Dovecot the server needs a key and a certificate. We simply take the Dovecot files for this purpose. And because the settings are for the SMTP server in the TLS complex, the parameter names start with 'smtpd_tls_'.

TLS is enabled with the parameter 'smtpd_tls_security_level', possible values are "none" for TLS disabled, "may" for TLS if the client wants to use it and "encrypt" for TLS-only communication. Although "encrypt" sounds like a good choice to ensure encryption, it is not; Postfix is not only waiting for our mail clients to connect and to receive mails to send to the outer world, it also waits for mails coming from the outer world to be delivered to one of our users. And we cannot assume that every mail server connecting to us is able use TLS. So we enable optional TLS with "may". Here is the new configuration:

*/etc/postfix/main.cf*
>mydomain = MAILDOMAIN
myhostname = MAILHOST.$mydomain
myorigin = $myhostname
mydestination = $myhostname
virtual_mailbox_domains = MAILDOMAIN
virtual_transport = lmtp:unix:private/dovecot-lmtp
smtpd_sasl_auth_enable = yes
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
**smtpd_tls_security_level = may**
**smtpd_tls_cert_file = /etc/dovecot/dovecot.pem**
**smtpd_tls_key_file = /etc/dovecot/private/dovecot.pem**

>`MAILROOT@MAILHOST# postfix reload`

In your mail client, switch the encryption setting for the outgoing server to "STARTTLS". STARTTLS is required because the connection to the mail server is starting unencrypted, as we have seen in our telnet sessions. The client can then switch to TLS encryption with the STARTTLS mechanism.

Try to send a mail, and you will most likely get a warning again about the self signed certificate. Accept the exception, send the mail and it should be delivered to the given destination.

For the next test, switch back the encryption setting for the outgoing server from "STARTTLS" to disabled encryption again. Try to send a mail, and it will succeed again - but this behaviour is actually unwanted, as we want to make sure our user password is not accidentally transferred readable over the internet due to a wrong mail client setting. This is the consequence of enabling TLS only as optional, the mail client is not required to use TLS.

Postfix offers the option that user authentication is only possible on a TLS encrypted connection (this includes connections which started unencrypted, but were switched to encrypted with STARTTLS) by setting the parameter 'smtpd_tls_auth_only':

*/etc/postfix/main.cf*
>mydomain = MAILDOMAIN
myhostname = MAILHOST.$mydomain
myorigin = $myhostname
mydestination = $myhostname
virtual_mailbox_domains = MAILDOMAIN
virtual_transport = lmtp:unix:private/dovecot-lmtp
smtpd_sasl_auth_enable = yes
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_tls_security_level = may
smtpd_tls_cert_file = /etc/dovecot/dovecot.pem
smtpd_tls_key_file = /etc/dovecot/private/dovecot.pem
**smtpd_tls_auth_only = yes**

>`MAILROOT@MAILHOST# postfix reload`

When you try to send one more test mail, an error message should now appear. The message will probably say something like "relay access denied". Set the encryption for the outgoing server to "STARTTLS", and the message will be sent.

This is the moment when we have a full functioning mail server: Mails from the internet are accepted and get placed into the user's mailboxes, users can access their mailboxes via IMAP, and users can send mails to the internet.

##Restrictions for unknown recipients and basic spam protection

Our mail server is accepting every mail which is delivered from the internet and is addressed to any "@<span></span>MAILDOMAIN" address. This includes spam mails from captured computers and mails to non-existing users in our domain. It would be helpful if those mails would be blocked before they are accepted by our mail server. This is done through restrictions. While a mail arrives, restrictions check whether certain criteria are met. A restriction check could result in rejecting the mail, or the mail is accepted without any further check, or subsequent checks should decide whether the mail is accepted or not.

Restriction checks can happen at different stages of the mail arrival. As we have seen in the SMTP sessions with telnet, the SMTP client is sending information step by step, each acknowledged by the SMTP server. After each such step, restrictions can be checked. Of course, some restrictions can only be performed after the relevant information is available, e.g. the check for an existing recipient cannot be done before the client announced the receiver address in the "RCPT TO:" stage. On the other hand, restriction checks do not need to be performed immediately after the relevant information has arrived, the checks can still be done in later stages.

The checks are performed in the order they are defined in the restrictions list.

There are several lists containing the checks to be performed depending on the stages:

- After a client connects to Postfix, the restrictions in 'smtpd_client_restrictions' are checked.

- After the client sent "HELO" (or "EHLO") the restrictions in 'smtpd_helo_restrictions' are checked.

- After the client sent "MAIL FROM:", the restrictions in 'smtpd_sender_restrictions' are checked.

- After the client sent "RCPT TO:", the restrictions in 'smtpd_recipient_restrictions' are checked.

- After the client sent "DATA", the restrictions in 'smtpd_data_restrictions' are checked.

The easiest way to define restrictions is to do all the checks at only one stage, when Postfix has gathered all information from the SMTP client. This is the case after receiving "RCPT TO:", so it is sufficient do put all checks in the 'smtpd_recipient_restrictions' list. And by the way, by default restriction checks are performed delayed, so even when a restriction check after "HELO" is performed and rejects the mail, the "MAIL FROM:" and "RCPT TO:" are still accepted before the mail is rejected.

So we will just define the parameter 'smtpd_recipient_restrictions' and put all the restrictions into this list. Here are some useful restrictions:

- Accept mail from clients connecting from the network definitions in 'mynetworks', the machines on the local network which are always trusted. The restriction name is 'permit_mynetworks'. This is also the default behaviour.

- If an outgoing mail is directed to a domain where no mail server is configured for, or if the domain does not exist, the mail should be rejected. The restriction name is 'reject_unknown_recipient_domain'.

- If the connecting mail client can successfully authenticate a user, this means the sender is a trusted user, the mail is accepted with no further checks. The restriction name is 'permit_sasl_authenticated'.

- If the sender of the mail does not wait for the acknowledgement of the server after sending the stages like "HELO" or "MAIL FROM:", and the client is not allowed to do so, reject the mail. This forces the mail client to correct behaviour. The restriction name is 'reject_unauth_pipelining'.

- If the recipient domain is not handled by Postfix, the mail should be rejected. This means that a mail directed to a domain not listed in the local domains, virtual domains or relay domains is not accepted. This prevents Postfix to work as an open relay and is very important. Note that this restriction should not apply to mails coming from authenticated users, as these mails are usually directed to those not-listed domains somewhere on the internet. So this restriction should come after 'permit_sasl_authenticated', which allows those mails. The name for this restriction is 'reject_unauth_destination'.

For the next restrictions, we take a look at the information Postfix can collect about the sender. During the handshake, the mail client tells its host name in the "HELO" part, which may not be correct - the mail client may even claim it is the mail server (in our case "MAILDOMAIN") itself. The IP address of the connecting mail client is also known.

Through DNS, Postfix can or could collect some more information:

1. From the claimed HELO host name, the for here called "claimed IP address" of the host can be determined.

2. From the "claimed IP address" from 1., through reverse DNS lookup, the host name of the "claimed IP address" can be determined.

3. From the IP address of the connecting mail client, called the "client IP address", through reverse DNS lookup, the "client host name" of the connecting client can be determined.

4. From the "client host name" from 3., through a regular DNS lookup, the IP address of the client host can be determined.

5. From the sender address ("MAIL FROM:"), the "sender domain" name can be extracted.

Based on these information, some more restrictions can be configured:

- A plausibility check on the IP address of the "client IP address" is performed: Determine the corresponding host name of the "client IP address" (3.), determine the IP address of this host name (4.) and check if this IP address matches the "client IP address"; if one of the lookups or the check fails, the mail is rejected. This blocks some captured computers without valid DNS entries from sending spam, as for a mail client to be accepted, the reverse DNS and the DNS for this name have to be configured correctly. Unfortunately, some internet service providers keep their DNS entries up-to-date, even for consumer internet connections with dynamic IP addresses, so not all captured computers are blocked this way. The restriction name is 'reject_unknown_client_hostname'.

- The "HELO host name" is checked if there is a valid DNS entry for this domain (2.). The resulting IP address is not compared to the "client IP address" (3.). By default, Postfix accepts connections from mail clients who do not send a "HELO" command; so to make this restriction effective, the parameter 'smtpd_helo_required' needs to be configured, too. The name for this restriction is 'reject_unknown_helo_hostname'.

- The "sender domain" is checked through DNS, if the domain has a valid mail server configured. If not, the mail is rejected. The restriction name is "reject_unknown_sender_domain".

- The receiver in the "RCPT TO:" part does not exist; in our configuration, Postfix asks Dovecot if the recipient is known to Dovecot, and if not, the mail is rejected. This does not apply to outgoing mail, as mails from authenticated users are accepted prior to this check. The name of this restriction is 'reject_unverified_recipient'.

- Finally, after all other restriction checks have been successfully performed, it should be signalled that the mail should be accepted. The restriction name is 'permit'.

There are more restrictions available, which can be found in http://www.postfix.org/postconf.5.html. Unfortunately, all restrictions Postfix offers are not listed in one place in the documentation, but they are distributed across the stage dependant restriction lists, when the restriction becomes available. Anyway, all the restrictions can be found on this page with a little search/research.

The restrictions presented here are just a first step to block spam. You likely want to add restrictions based on actively maintained lists of known spamming mail clients. This is not described here.

To install the presented restriction, add it to the configuration:

*/etc/postfix/main.cf*
>mydomain = MAILDOMAIN
myhostname = MAILHOST.$mydomain
myorigin = $myhostname
mydestination = $myhostname
virtual_mailbox_domains = MAILDOMAIN
virtual_transport = lmtp:unix:private/dovecot-lmtp
smtpd_sasl_auth_enable = yes
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_tls_security_level = may
smtpd_tls_cert_file = /etc/dovecot/dovecot.pem
smtpd_tls_key_file = /etc/dovecot/private/dovecot.pem
smtpd_tls_auth_only = yes
**smtpd_helo_required = yes**
**smtpd_recipient_restrictions =**
**permit_mynetworks,**
**reject_unknown_recipient_domain,**
**permit_sasl_authenticated,**
**reject_unauth_pipelining,**
**reject_unauth_destination,**
**reject_unknown_client_hostname,**
**reject_unknown_helo_hostname**
**reject_unknown_sender_domain**
**reject_unverified_recipient,**
**permit**

__*The restrictions must be indented, currently this can't be displayed here; add spaces or tabs before each permit\_ and reject\_*__

>`MAILROOT@MAILHOST# postfix reload`


##Some more useful settings

There are some more settings which are not really required, but are useful. Here they are:

###Postfix

To support some mail clients which have a non standard conform behaviour with SASL, add the parameter

*/etc/postfix/main.cf*
>broken_sasl_auth_clients = yes

It doesn't have any drawbacks, but supports those broken mail clients.

###Dovecot

No further settings so far.

##All files incorporated

### */etc/postfix/main.cf*
```
mydomain = MAILDOMAIN
myhostname = MAILHOST.$mydomain
myorigin = $myhostname
mydestination = $myhostname

virtual_mailbox_domains = MAILDOMAIN
virtual_transport = lmtp:unix:private/dovecot-lmtp

smtpd_sasl_auth_enable = yes
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
broken_sasl_auth_clients = yes

smtpd_tls_security_level = may
smtpd_tls_cert_file = /etc/dovecot/dovecot.pem
smtpd_tls_key_file = /etc/dovecot/private/dovecot.pem
smtpd_tls_auth_only = yes

smtpd_helo_required = yes

smtpd_recipient_restrictions =
  permit_mynetworks,
  reject_unknown_recipient_domain,
  permit_sasl_authenticated,
  reject_unauth_pipelining,
  reject_unauth_destination,
  reject_unknown_client_hostname,
  reject_unknown_helo_hostname
  reject_unknown_sender_domain
  reject_unverified_recipient,
  permit
```

### */etc/dovecot/dovecot.conf*

```
protocols = imap lmtp

mail_gid = vmail
mail_uid = vmail
mail_home = /var/vmail/%d/%n
mail_location = maildir:~/mail
postmaster_address = postmaster @MAILDOMAIN
hostname = MAILHOST

passdb {
  driver = passwd-file
  args = scheme=PLAIN /etc/dovecot/users.db
}

ssl = required
ssl_cert = </etc/dovecot/dovecot.pem
ssl_key = </etc/dovecot/private/dovecot.pem

service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    user = postfix
    group = postfix
    mode = 0600
  }
}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    user = postfix
    group = postfix
    mode = 0600
  }
}
```

### */etc/dovecot/users.db*
```
MAILUSER@MAILDOMAIN:$6$g6adDoglZXU5CJq1$AMojgOJQPtdEEGt1MW86YZUDMlf1Wi6QLz6RH.7BHJpNzjQmYpRmP./IN0eRP8.eLAmEcnoRtzrS1jonKQT9k/`
```

##Next steps

Based on this configuration, you can start making extensions. Recommended next steps may include:

- Create mandatory administration mail addresses, depending on the services your network provides, like "postmaster" or "webmaster".

- Create alias mail addresses for the administration mail adresses; alias addresses are addresses which do not have a configured mail user, but are mapped to an existing user. An example would be to create an alias for "postmaster@<span></span>MAILDOMAIN", which is mapped to "MAILUSER@<span></span>MAILDOMAIN" and mail for "postmaster" arrives in the mailbox of MAILUSER.

- Remove the configuration for the local domain from Postfix, if you want to have a pure virtual mail server. This may be the case when you know that you will never look for locally delivered mail on the mail server.

- Add spam protection with the help of block lists.

##When mail does not arrive

During the test, especially when sending mails from our mail server to a public mail server on the internet, the mail may not arrive or is rejected by the receiving mail server. A look at the logs usually explains the problem.

Typical difficulties are:

- The reverse DNS entry is not set, and the receiving mail server checks for this DNS entry

- Your public IP address is marked as a potential spam source on spam blocking lists. This may be because your static IP address lies in a range of normally dynamic IP addresses.

There are some service websites which check a variety of often used spam blocking lists whether your mail server / your IP address is on their lists. When you find a list which blocks your server, you need to contact this list and ask for an exception, typically through an automated web form.

## Todo

- Insert links to Postfix and Dovecot documentation where the topics are explained deeper

- Create a list of mandatory mail addresses

## Info

Page created: DATE

This page is licensed under the Creative Commons license and is hosted under

https://github.com/agodes/mailserver-step-by-step


Copyright (c) 2016 Norbert Roos <<nroos@agodes.com>\>
