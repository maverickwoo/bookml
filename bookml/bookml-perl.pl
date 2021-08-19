# -*- mode: Perl -*-
# vim: syntax=perl

=begin comment

  BookML: bookdown flavoured GitBook port for LaTeXML
  Copyright (C) 2021  Vincenzo Mantova <v.l.mantova@leeds.ac.uk>

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.

=end comment

=cut

package LaTeXML::Package::Pool;
use strict;
use warnings;

use LaTeXML::Package;
use LaTeXML::Util::Pathname;

use IPC::Open3;
use XML::LibXML;

my ($bmlProgressSpinup, $bmlProgressSpindown, $bmlProgressStep, $bmlNote, $bmlNoteDetailed);

if (!defined &ProgressSpinup) {
  # pre-0.8.6 reporting
  $bmlProgressSpinup   = \&NoteBegin;
  $bmlProgressSpindown = \&NoteEnd;
  $bmlProgressStep     = sub { my $text = shift; if (defined $text) { \&NoteProgress("\n$text"); } };
  $bmlNote             = sub { my $text = shift; if (defined $text) { \&NoteProgress("\n$text"); } };
  $bmlNoteDetailed = sub { my $text = shift; if (defined $text) { \&NoteProgressDetailed("\n$text"); } };
} else {
  $bmlProgressSpinup   = \&ProgressSpinup;
  $bmlProgressSpindown = \&ProgressSpindown;
  $bmlProgressStep     = \&ProgressStep;
  $bmlNote             = \&Note;
  $bmlNoteDetailed     = \&NoteLog;
}

# Helper function to add resources at the *end* of head or body
# Partly copied from RequireResource
my $bml_resource_options = {
  type => 1, location => 1, content => 1 };
my $bml_resource_types = {
  css => 'text/css', js => 'text/javascript', ttf => 'font/ttf', pdf => 'application/pdf' };

sub BMLRequireResource {
  my ($resource, %options) = @_;
  CheckOptions('BMLRequireResource', $bml_resource_options, %options);

  if (!$options{content} && !$resource) {
    Warn('expected', 'resource', undef, 'Resource must have a resource pathname or content; skipping');
    return; }

  if (!$options{location}) {
    $options{location} = 'head'; }

  if (!$options{type}) {
    my $ext = $resource && pathname_type($resource);
    $options{type} = $ext && $$bml_resource_types{$ext}; }
  if (!$options{type}) {
    Warn('expected', 'type', undef, 'Resource must have a mime-type; skipping');
    return; }
  $options{type} .= ';bmllocation=' . $options{location};

  delete $options{location};
  return RequireResource($resource, %options);
}

my $bml_gitbook    = 1;
my $bml_imagescale = 96 / 72;
my $bml_fontscale  = 1;

DeclareOption('nogitbook', sub { $bml_gitbook = 0; return; });
DeclareOption('mathjax=2');
DeclareOption('nomathjax');
for my $pt (5..28) {
  DeclareOption($pt . 'pt', sub {
      $bml_fontscale  = 10 / $pt;
      $bml_imagescale = 96 / 72 * $bml_fontscale;
      return;
  });
}

DefConditional('\ifbmlGitBook', sub { $bml_gitbook; });

DeclareOption(undef, sub {
    my ($stomach) = @_;
    my $opt = ToString(Expand(T_CS('\CurrentOption')));
    if ($opt =~ m/^imagescale\s*=\s*(.*)$/) {
      my $val = $1;
      if ($val =~ m/^(?:\d+|\d*\.\d+)$/) {
        $bml_imagescale = $bml_fontscale * $val; }
      else {
        Error('malformed', $opt, $stomach, "Value '$val' of imagescale= for bookml.sty must be a decimal number"); } }
    else {
      Error('unexpected', $opt, $stomach, "Unexpected option '$opt' passed to bookml.sty"); }
    return;
});

ProcessOptions();

RequirePackage('latexml', options => ['nocomments', 'noguesstabularheaders']);

if ($bml_gitbook) {
  # anywhere in the head
  for my $res (qw(
    bookml/jquery/jquery.min.js
    bookml/gitbook/css/style.css
    bookml/gitbook/css/plugin-table.css
    bookml/gitbook/css/plugin-bookdown.css
    bookml/gitbook/css/plugin-fontsettings.css
    bookml/gitbook/css/plugin-clipboard.css
    bookml/gitbook-style.css
    )) { RequireResource($res); }

  # end of body
  for my $res (qw(
    bookml/gitbook/js/app.min.js
    bookml/gitbook/js/clipboard.min.js
    bookml/gitbook/js/plugin-fontsettings.js
    bookml/gitbook/js/plugin-bookdown.js
    bookml/gitbook/js/plugin-clipboard.js
    )) { BMLRequireResource($res, location => 'body'); }

  # additional files to be copied over
  RequireResource('bookml/gitbook/css/fontawesome/fontawesome-webfont.ttf', type => 'font/ttf');
  RequireResource(ToString(Expand(T_CS('\jobname'))) . '.pdf', type => 'application/pdf');
} else {
  RequireResource('bookml/nogitbook-style.css');
}

AtBeginDocument(sub {
    RequireResource('bookml/style.css');
});

# HTML-in-LaTeX mechanism
DefPrimitive('\bmlHTMLEnvironment{}', sub {
    my ($gullet, $name) = @_;
    $name = ToString(Expand($name));

    DefEnvironment("{h:$name} OptionalKeyVals", sub {
        my ($document, $kv, %properties) = @_;
        my $body = $properties{body};
        $kv = $kv && $kv->getKeyVals;

        # convert the options to serialised xml attributes
        my @attrs = ();
        for my $key (keys %$kv) {
          my $attr = XML::LibXML::Attr->new($key, ToString($$kv{$key}));
          my $val  = $attr->serializeContent();
          if (!defined $val) { $val = ''; }
          push(@attrs, "$key=\"$val\""); }
        my $attrs = @attrs ? join(' ', @attrs) : undef;

        # <$name $attrs>
        my $node = $document->insertElement('ltx:rawliteral', $attrs, open => $name);
        $document->absorb($body);                     # emit content of the environment
        $document->closeToNode($node->parentNode);    # close everything

        # </$name>
        $document->insertElement('ltx:rawliteral', undef, open => "/$name");
    });
});

# Raw HTML mechanism

# import fontenc after \documentclass to allow for --preload=bookml
AtBeginDocument( sub { RequirePackage('fontenc', options => ['T1']); });
my $parser = XML::LibXML->new();

DefConstructor('\bmlRawHTML Digested', sub {
    my ($document, $arg) = @_;

    # wrap in <span> to set the XHTML namespace
    my $html = $parser->parse_balanced_chunk('<span xmlns="http://www.w3.org/1999/xhtml">' . ToString($arg) . '</span>');
    my @elems = $html->firstChild->findnodes('*');

    my $node = $document->openElement('ltx:rawhtml');
    map { $document->appendClone($node, $_) } @elems;
    $document->closeElement('ltx:rawhtml');
  }
);

# Image generation via LaTeX
NewCounter('bml@imagecounter');
DefMacro('\bml@includeimage', '\stepcounter{bml@imagecounter}\includegraphics{bmlimages/\jobname-\thebml@imagecounter.svg}');

sub BMLImageEnvironment {
  my ($gullet, $name) = @_;
  $name = ToString($name);
  AtBeginDocument(sub {
      RequirePackage('graphicx');
      DefMacroI(T_CS("\\begin{$name}"), undef, sub {
          my ($ingullet) = @_;
          while ($ingullet->readUntil(T_CS('\end'))) {
            my $arg = $ingullet->readArg;
            last if (ToString($arg) eq $name);
          }
          return T_CS('\bml@includeimage');
      });
  });
  return;    # or perltidy complains
}

DefPrimitive('\bmlImageEnvironment{}', \&BMLImageEnvironment);

BMLImageEnvironment(undef, 'preview');    # predefined by the preview package
BMLImageEnvironment(undef, 'bmlimage');

AtEndDocument(sub {
    my ($gullet) = @_;

    # skip if there are no images to generate
    return unless CounterValue('bml@imagecounter')->valueOf;

    &$bmlProgressSpinup('BookML generating bmlimages');

    # code to activate preview and add dvisvgm as global option
    my $preclass = '\PassOptionsToPackage{active}{preview}';        # activate preview
    $preclass .= '\makeatletter';
    $preclass .= '\let\bml@dcl@ss\documentclass';                   # save \documentclass
    $preclass .= '\renewcommand{\documentclass}[1][]{';             # renew \documentclass[]
    $preclass .= '\def\bml@dcl@ss@pts{#1}';                         # save options
    $preclass .= '\let\documentclass\bml@dcl@ss';                   # restore \documentclass
    $preclass .= '\ifx\bml@dcl@ss@pts\@empty';                      # no options?
    $preclass .= '\def\bml@dcl@ss@{\documentclass[dvisvgm]}';       # add dvisvgm
    $preclass .= '\else';                                           # with options?
    $preclass .= '\def\bml@dcl@ss@{\documentclass[dvisvgm,#1]}';    # prepend dvisvgm
    $preclass .= '\fi\bml@dcl@ss@}';                                # close definition
    $preclass .= '\makeatother';

    my $jobname = ToString(Expand(T_CS('\jobname')));
    my $source  = LookupValue('SOURCEFILE');
    my $outdir  = pathname_concat('bmlimages', 'out');
    my $dvifile = pathname_concat($outdir,     $jobname . '.dvi');
    my $svgfmt  = pathname_concat('bmlimages', '%f-%0p.svg');

    # compile $source to DVI with latexmk
    my @lmk_invocation = ('latexmk', '-output-format=dvi',
      '-interaction=nonstopmode', '-quiet', '-halt-on-error',
      '-output-directory=' . $outdir, '-usepretex=' . $preclass,
      '-jobname=' . $jobname,         $source);
    if ($^O =~ /^(MSWin|cygwin)/) {
      require Win32::ShellQuote;
      @lmk_invocation = Win32::ShellQuote::quote_system_list->(@lmk_invocation); }
    &$bmlNoteDetailed('Calling ' . join(' ', @lmk_invocation));
    &$bmlNoteDetailed('Logs in ' . pathname_concat($outdir, $jobname . '.log'));
    my $lmk_pid = IPC::Open3::open3(undef, my $lmk_stdout, undef,
      @lmk_invocation);

    my $rebuilt = 0;

    # report progress and remember if latexmk did anything
    while (<$lmk_stdout>) {
      $rebuilt = 1;
      if (m/^Latexmk: Run number (.*)/) {
        &$bmlProgressStep("latexmk: run number $1"); }
      else { &$bmlProgressStep(); }
      chomp $_;
      &$bmlNoteDetailed($_);
    }

    close($lmk_stdout);
    waitpid($lmk_pid, 0);

    # if latexmk rebuilt the DVI, rebuild the images as well
    if ($rebuilt) {
      # convert DVI to images
      my @dsvg_invocation = ('dvisvgm', '--page=1-', '--bbox=1pt',
        '--no-fonts', '--exact', '--optimize', '--zoom=' . $bml_imagescale,
        '--output=' . $svgfmt, $dvifile);
      if ($^O =~ /^(MSWin|cygwin)/) {
        require Win32::ShellQuote;
        @dsvg_invocation = Win32::ShellQuote::quote_system_list->(@dsvg_invocation); }
      &$bmlNoteDetailed('Calling ' . join(' ', @dsvg_invocation));
      my $dsvg_pid = IPC::Open3::open3(undef, my $dsvg_stdout, undef,
        @dsvg_invocation);

      # report progress
      while (<$dsvg_stdout>) {
        $rebuilt = 1;
        if (m/^processing page (\d+)/) {
          &$bmlProgressStep("dvisvgm: processing image $1"); }
        else { &$bmlProgressStep(); }
        chomp $_;
        &$bmlNoteDetailed($_);
      }

      close($dsvg_stdout);
      waitpid($dsvg_pid, 0); }

    &$bmlProgressSpindown('BookML generating bmlimages');

    return;
});

# Alternative text
DefConstructor('\bmlDescription Semiverbatim', sub {
    my ($document, $text) = @_;
    my $node = $document->getLastChildElement($document->getElement);
    $document->setAttribute($node, 'description', ToString($text));
});

# Add class to previous node
DefConstructor('\bmlPlusClass Semiverbatim', sub {
    my ($document, $class) = @_;
    my $node = $document->getLastChildElement($document->getElement);
    $document->addClass($node, ToString($class));
});

1;
