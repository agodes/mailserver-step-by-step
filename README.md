# mailserver-step-by-step
Tutorial for basic Postfix/Dovecot installation, step by step

The tutorial explains step by step how to set up a very basic yet working mail server with Postfix and Dovecot for IMAP access. A SQL database is not involved.

This project contains the tutorial formatted in github markdown and a script to convert it to a HTML page.

## Prerequisites

The tool 'pandoc' is used and needs to be installed.

## HTML page creation

The source text contains some variables which must be defined in the file 'variables'. With these variables, the host and domain names used in the tutorial are configured.

Each line in 'variables' contains one variable definition; first the variable name and seperated by space the variable value, without '='.

To create the page:

- Edit 'variables'; the variable "DATE" is replaced by 'create.bash"

- run './create.bash'

The generated page has the name 'mailserver-step-by-step.html'.

## License

The tutorial is distributed under the Creative Common License.
