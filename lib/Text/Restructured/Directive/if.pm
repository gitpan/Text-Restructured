# $Id: if.pm 5067 2007-05-04 22:38:58Z mnodine $
# Copyright (C) 2002-2005 Freescale Semiconductor, Inc.
# Distributed under terms of the Perl license, which is the disjunction of
# the GNU General Public License (GPL) and the Artistic License.

# This package implements the perl directive for the perl implementation
# of reStructuredText.

package Text::Restructured::Directive::if;

$VERSION = ( q$Revision: 768$ ) =~ /(\d+)/g;

=pod
=begin reST
=begin Description
Executes its argument as a perl expression and returns its
content if the perl expression is true.  The content is
interpreted as reStructuredText.  It has no options. It processes
the following defines:

-D perl='perl-code'
                Specifies some perl code that is executed prior
                to evaluating the first perl directive.  This
                option can be used to specify variables on the
                command line; for example::

                  -D perl='$a=1; $b=2'

                defines constants ``$a`` and ``$b`` that can
                be used in the perl expression.
-D trusted      Must be specified for if directives to use any
                operators normally masked out in a Safe environment.
                This requirement is to prevent an if directive in a
                file written elsewhere from doing destructive things
                on your computer.
=end Description
=end reST
=cut

BEGIN {
    Text::Restructured::Directive::handle_directive
	('if', \&Text::Restructured::Directive::if::main);
}

# Plug-in handler for if directives.
# Arguments: directive name, parent, source, line number, directive text, 
#            literal text
# Returns: array of DOM objects
sub main {
    my($parser, $name, $parent, $source, $lineno, $dtext, $lit) = @_;
    my $dhash = Text::Restructured::Directive::parse_directive
	($parser, $dtext, $lit, $source, $lineno, [], '1+');
    return $dhash if ref($dhash) eq "Text::Restructured::DOM";
    my($args, $options, $content) =
	map(defined $dhash->{$_} ? $dhash->{$_} : '',
	    qw(args options content));
    return Text::Restructured::Directive::system_msg
	($parser, $name, 3, $source, $lineno,
	 qq(The $name directive must have content.), $lit)
	if $content =~ /^$/;
    if (! $Perl::safe) {
	# Create a safe compartment for the Perl to run
	use Safe;
	$Perl::safe = new Safe "Perl::Safe";
	# Grant privileges to the safe if -D trusted specified
	$Perl::safe->mask(Safe::empty_opset()) if $parser->{opt}{D}{trusted};
	# Share $opt_ variables, $^A to $^Z, %ENV, STDIN, STDOUT, STDERR,
	# VERSION
	my @vars = grep(/^[\x00-\x1f]|^(ENV|STD(IN|OUT|ERR)|VERSION)\Z/,
			keys %main::);
	foreach (@vars) {
	    local *var = $main::{$_};
	    *{"Perl::Safe::$_"} = *var;
	}
	# Share $opt_ variables
 	foreach (keys %{$parser->{opt}}) {
	    my $opt = $parser->{opt}{$_};
	    if (ref $opt eq 'ARRAY') {
		*{"Perl::Safe::opt_$_"} = \@$opt;
	    }
	    elsif (ref $opt eq 'HASH') {
		*{"Perl::Safe::opt_$_"} = \%$opt;
	    }
	    else {
		*{"Perl::Safe::opt_$_"} = \$opt;
	    }
 	}
	# Share RST and DOM subroutines
	foreach (keys %Text::Restructured::) {
	    local *opt = $Text::Restructured::{$_};
	    no strict 'refs';
	    *{"Perl::Safe::Text::Restructured::$_"} = \&{"Text::Restructured::$_"} if defined &{"Text::Restructured::$_"};
	}
	foreach (keys %Text::Restructured::DOM::) {
	    local *opt = $Text::Restructured::DOM::{$_};
	    no strict 'refs';
	    *{"Perl::Safe::Text::Restructured::DOM::$_"} =
		\&{"Text::Restructured::DOM::$_"}
	    if defined &{"Text::Restructured::DOM::$_"};
	}
    }
    $Perl::Safe::SOURCE = $source;
    $Perl::Safe::LINENO = $lineno;
    $Perl::Safe::TOP_FILE = $parser->{TOP_FILE};
    @Perl::Safe::INCLUDES = @Text::Restructured::INCLUDES;

    if (defined $parser->{opt}{D}{perl}) {
	my $exp = $parser->{opt}{D}{perl};
	$Perl::safe->reval($exp);
	delete $parser->{opt}{D}{perl};
	my $err = $@ =~ /trapped by/ ? "$@Run with -D trusted if you believe the code is safe" : $@;
	return $parser->system_message
	    (4, $source, $lineno,
	     qq(Error executing "-D perl" option: $err.),$exp)
	    if $@;
    }

    my $val = $Perl::safe->reval("$args");
    my $err = $@ =~ /trapped by/ ? "$@Run with -D trusted if you believe the code is safe" : $@;
    return $parser->system_message
	(4, $source, $lineno,
	 qq(Error executing "$name" directive: $err.), $lit)
	if $@;
    return '' unless $val;
    my $newsource = qq($name directive at $source, line $lineno);
    if ($parent->{tag} eq 'substitution_definition') {
	my @doms;
	my $fake = new Text::Restructured::DOM('fake');
	$parser->Paragraphs($fake, $content, $newsource, 1);
	my $last = $fake->last();
	if (@{$fake->{content}} == 1 && $last->{tag} eq 'paragraph') {
	    chomp $last->{content}[-1]{text} if $last->{content}[-1]{text};
	    return @{$last->{content}};
	}
	push(@doms, grep($_->{tag} eq 'system_message' && do {
	    delete $_->{attr}{backrefs}; 1}, @{$fake->{content}}));
	push @doms, $parser->system_message(3, $source, $lineno,
					    qq(Error in "$name" directive within substitution definition: may contain a single paragraph only.));
	return @doms;
    }
    else {
	$parser->Paragraphs($parent, "$content\n", $newsource, 1);
    }

    return;
}

1;
