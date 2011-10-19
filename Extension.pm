# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the FlagTypeComment Bugzilla Extension.
#
# The Initial Developer of the Original Code is Alex Keybl 
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Alex Keybl <akeybl@mozilla.com>

package Bugzilla::Extension::FlagTypeComment;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::FlagType;

use constant NAME => 'FlagTypeComment';
our $VERSION = '0.01';

my(@attachtemplates) = ("attachment/edit.html.tmpl","attachment/create.html.tmpl");
my(@bugtemplates) = ("bug/comments.html.tmpl");
my(@admintemplates) = ("admin/flag-type/edit.html.tmpl","admin/flag-type/list.html.tmpl");
my(@states) = ("?","+","-");

################
# Installation #
################

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'flagtypecomments'} = {
        FIELDS => [
            flagtype     =>    {TYPE => 'SMALLINT(6)', NOTNULL => 1,
                                REFERENCES => {TABLE  => 'flagtypes',
                                               COLUMN => 'id',
                                               DELETE => 'CASCADE'}},
            on_status       => {TYPE => 'CHAR(1)', NOTNULL => 1},
            comment_prepend => {TYPE => 'MEDIUMTEXT', NOTNULL => 1}, 
        ],
        INDEXES => [
            flagtypecomments_flagtype_idx => ['flagtype'],
        ],
    };
}

#############
# Templates #
#############

sub template_before_process {
    my ($self, $args) = @_;

    my ($vars, $file, $context) = @$args{qw(vars file context)};

    my $flagtypes;

    if ( grep {$_ eq $file} @attachtemplates ) {
       if (Bugzilla->cgi->param('action') eq "enter" ) {
          $flagtypes = $vars->{'flag_types'};
       }
       else {
          $flagtypes = $vars->{'attachment'}->flag_types;
       }
    } elsif ( grep {$_ eq $file} @bugtemplates ) {
       $flagtypes = $vars->{'bug'}->flag_types;
    }

    if ( defined $flagtypes ) {
       _use_flags($vars, $flagtypes);
    }
    elsif ( grep {$_ eq $file} @admintemplates ) {
       if ( $vars->{'last_action'} eq "edit" || $vars->{'last_action'} eq "enter" ) {
          _before_set_flag($vars);
       }
       elsif ( Bugzilla->cgi->param('action') eq "update" ) {
          _set_flag(Bugzilla->cgi->param('id'));
       } elsif ( Bugzilla->cgi->param('action') eq "insert" ) {
          _set_flag(Bugzilla->dbh->bz_last_key('flagtypes', 'id'));
       }
    }
}

######################
# Helper Subroutines #
######################

sub _use_flags {
   my ($vars, $flagtypes) = @_;

   my $dbh = Bugzilla->dbh;
    
   my $db_base = "SELECT * FROM flagtypecomments WHERE ";
   my $db_query = "$db_base";

   foreach my $flag_type (@$flagtypes) {
      if ( $db_query ne $db_base ) {
         $db_query = $db_query . "OR ";
      }

      $db_query = $db_query . "flagtype=" . $dbh->quote($flag_type->id);  
   }

   if ( $db_query ne $db_base ) {
      $vars->{flag_type_comments} =  $dbh->selectall_arrayref( "$db_query", {Slice=>{}} );
   }
}

sub _before_set_flag {
   my ($vars) = @_;

   my $type = $vars->{'type'};

   $vars->{'states'}=\@states;

   if ( $vars->{'last_action'} eq "edit" ) {
      my $dbh = Bugzilla->dbh;

      my %texts=();

      foreach my $state (@states) {
         my $db_query = "SELECT comment_prepend FROM flagtypecomments WHERE flagtype=" . $dbh->quote($type->id) . " AND on_status=" . $dbh->quote($state);
         my $text =  $dbh->selectrow_array( "$db_query", {Slice=>{}} );
             
         if ( $text ) {
            $texts{ $state } = $text;
         }
      }

      if ( keys %texts ) {
         $vars->{'texts'}=\%texts;
      }
   }
}

sub _set_flag {
   my ($tid) = @_;

   my $cgi = Bugzilla->cgi;
   my $dbh = Bugzilla->dbh;

   if ($tid =~ /^(\d+)$/) {
      $tid = $1;
   }

   my $i = 0;

   foreach my $state (@states) {
      my $cid = "ftc_text_$i";              
      my $text = $cgi->param($cid);

      $text =~ s/\r\n/\\n/g;
      $text =~ s/\'/\\'/g;

      if ($text =~ m/(.+)/) {
         $text = $1;
      }

      if ( $text ne "" ) {
         my $db_query = "SELECT comment_prepend FROM flagtypecomments WHERE flagtype=" . $dbh->quote($tid) . " AND on_status=" . $dbh->quote($state);

         if ( $dbh->selectrow_array( "$db_query", {Slice=>{}} ) ) {
            my $sth = $dbh->prepare("UPDATE flagtypecomments SET comment_prepend = ? WHERE flagtype=" . $dbh->quote($tid) . " AND on_status=" . $dbh->quote($state) );
            $sth->bind_param_array(1, $text);
            $sth->execute_array(undef) or die $sth->errstr;
            $sth->finish();
         } else {
            my $sth = $dbh->prepare("INSERT INTO flagtypecomments (flagtype, on_status, comment_prepend) VALUES (?, ?, ?)");
            $sth->bind_param_array(1, $tid);
            $sth->bind_param_array(2, $state);
            $sth->bind_param_array(3, $text);
            $sth->execute_array(undef) or die $sth->errstr;
            $sth->finish();
         }
      }
      else {
         my $sth = $dbh->prepare("DELETE FROM flagtypecomments WHERE flagtype=" . $dbh->quote($tid) . " AND on_status=" . $dbh->quote($state) ); 
         $sth->execute or die $sth->errstr;
         $sth->finish();
      }

      $i++; 
   } 
}

__PACKAGE__->NAME;
