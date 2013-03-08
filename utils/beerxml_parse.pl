#!/usr/bin/perl -w
#
# TODO: heuristically determine extract vs all grain type

use strict;
use Getopt::Std;
use XML::Simple;
use Text::Wrap;
use Data::Dumper;

my $CSS = "brew.css";
my $LINKCSS = 0;
my $NOTES = 0;

sub reftype ($) {
  my ($ref) = @_;
  if (ref ($ref) eq 'ARRAY') {
    return (@{$ref});
  } else {
    return ($ref);
  }
}

sub l2g ($) {
  my ($l) = @_;
  return ($l * 0.26417205);
};

sub fractionformat ($) {
  my ($amount) = @_;
  my $fraction = $amount;
  if ($amount == 0.125) { $fraction = '1/8' }
  if ($amount == 0.25) { $fraction = '1/4' }
  if ($amount == 0.375) { $fraction = '3/8' }
  if ($amount == 0.5) { $fraction = '1/2' }
  if ($amount == 0.625) { $fraction = '5/8' }
  if ($amount == 0.75) { $fraction = '3/4' }
  if ($amount == 0.875) { $fraction = '7/8' }

  return ($fraction);
}

sub numchop ($) {
  my ($n) = @_;
  # strip zeroes
  $n =~ s/0+$//;
  $n =~ s/\.$//;
  # strip leading spaces
  $n =~ s/^\s+//;
  return ($n);
}

sub amtchop ($) {
  my ($amt) = @_;
  my ($num, $units) = (split (/\s+/, $amt, 2));
  $num = fractionformat (numchop ($num));
  return ("$num $units");
}

sub kgconvert ($) {
  my ($amount) = @_;

  $amount = $amount * 2.2046226;

  if ($amount < 1) {
    $amount = $amount * 16;
    $amount = amtchop (sprintf ("%1.3f oz", $amount));
  } else {
    if (int ($amount) != $amount) {
      my $rem = $amount - int ($amount);
      $rem = $rem * 16;
      $amount = int ($amount);
      $amount = numchop (sprintf ("%1.0f", $amount)) . " lb";
      $rem = numchop (sprintf ("%2.0f", $rem)) . " oz";
      $amount = "$amount $rem";
    } else {
      $amount = amtchop (sprintf ("%1.0f lb", $amount));
    }
  }

  return ($amount);
}

sub volformat ($) {
  my ($amount) = @_;

  if ($amount < 0.0147867) { # tbsp cutoff
    # teaspoons
    $amount = $amount * 202.88414;
    $amount = sprintf ("%1.3f tsp", $amount);
#  } elsif ($amount < 0.236588) { # cup cutoff
  } elsif ($amount < 0.05914706) { # 1/4 cup cutoff
    # tablespoons
    $amount = $amount * 67.628045;
    $amount = sprintf ("%1.1f tbsp", $amount);
  } elsif ($amount < 0.946352) {
    # cups
    $amount = $amount * 4.2267528;
    $amount = sprintf ("%2.2f cup", $amount);
  } elsif ($amount < 3.78541) {
    # quarts
    $amount = $amount * 1.0566882;
    $amount = sprintf ("%1.2f qt", $amount);
  } else {
    # gallons
    $amount = $amount * 0.26417205;
    $amount = sprintf ("%1.3f gal", $amount);
  }

  return (amtchop ($amount));
}

sub c2f ($) {
  my ($c) = @_;
  my $f = $c * 9 / 5 + 32;
  return ($f);
}

sub fahrentemp ($) {
  my ($temp) = @_;
  if ($temp =~ /^([\d\.]+)\sF$/) {
    return ($1);
  } else {
    return (c2f ($temp));
  }
}

sub abv ($$) {
  my ($og, $fg) = @_;
  return (((1.05 * ($og - $fg)) / $fg) / 0.79 * 100);
}

sub ibu ($$$$$) {
  my ($alpha, $amount, $gravity, $time, $volume) = @_;
  my ($utilization, $fG, $fT, $aau, $ibu);

  $volume = $volume / 3.7854118;

  $amount = $amount * 2.2046226 * 16;

  $fG = 1.65 * 0.000125 ** ($gravity - 1);
  $fT = (1 - exp(1) ** (-0.04 * $time)) / 4.15;
  $utilization = $fG * $fT;

  $aau = $amount * $alpha;

  $ibu = $aau * $utilization * 74.89 / $volume;

  return ($ibu);
}

sub processFermentables ($@) {
  my ($data, @ferm) = @_;
  my $volume = l2g ($data->{'BATCH_SIZE'});
  $data->{'FERMENTABLES_WEIGHT'} = 0;

  foreach my $f (@ferm) {
    my $ferm;
    $ferm->{'Name'} = $f->{'NAME'};
    $ferm->{'Type'} = $f->{'TYPE'};
    $ferm->{'Yield'} = $f->{'YIELD'};
    $ferm->{'Amount'} = $f->{'AMOUNT'};
    $ferm->{'amtype'} = 'weight';
    $ferm->{'Color'} = $f->{'COLOR'};
    if ($ferm->{'Type'} =~ /^(Grain|Adjunct)$/i) {
      $ferm->{'Mashed'} = 'Yes';
    } else {
      $ferm->{'Mashed'} = 'No';
    }
    $ferm->{'MCU'} = $ferm->{'Color'} * $ferm->{'Amount'} * 2.2046226 / $volume;
    $ferm->{'sort'} = $ferm->{'Amount'};

    $data->{'MCU'} += $ferm->{'MCU'};
    $data->{'FERMENTABLES_WEIGHT'} += $ferm->{'Amount'};
    push @{$data->{'FERMENTABLES'}}, $ferm;
  }
  foreach my $f (@{$data->{'FERMENTABLES'}}) {
    # calculate percentage
    $f->{'%'} = $f->{'Amount'} / $data->{'FERMENTABLES_WEIGHT'} * 100.0;
  }

  $data->{'SRM'} = 1.4922 * ($data->{'MCU'} ** 0.6859);

  my $weight = displayUnit ($data->{'FERMENTABLES_WEIGHT'}, 'Amount', 'weight');
  my $color = displayUnit ($data->{'SRM'}, 'Color', '') . ' (Morey)';

  #$data->{'HEADERS'}->{'FERMENTABLES'} = [ '%', "Name", "Type", "Amount", "Mashed", "Yield", "Color", "MCU" ];
  $data->{'HEADERS'}->{'FERMENTABLES'} = [ '%', "Name", "Type", "Amount", "Mashed", "Yield", "Color" ];
  #$data->{'HEADERS'}->{'FERMENTABLES'} = [ '%', "Name", "Amount", "Mashed", "Yield", "Color" ];
  $data->{'CAPTIONS'}->{'FERMENTABLES'} = "Total grain: $weight / Color: $color";
}

sub processHops ($@) {
  my ($data, @hops) = @_;

  $data->{'IBU'} = 0;
  $data->{'HOPS_WEIGHT'} = 0;

  foreach my $h (@hops) {
    my $hops;
    $hops->{'Name'} = $h->{'NAME'};
    $hops->{'Alpha'} = $h->{'ALPHA'};
    $hops->{'Amount'} = $h->{'AMOUNT'};
    $hops->{'amtype'} = 'weight';
    $hops->{'Use'} = $h->{'USE'};
    $hops->{'Time'} = $h->{'TIME'};
    $hops->{'Form'} = $h->{'FORM'};
    if ($h->{'USE'} eq 'Boil') {
      $hops->{'IBU'} = ibu ($hops->{'Alpha'}, $hops->{'Amount'}, $data->{'SG'}, $hops->{'Time'}, $data->{'BATCH_SIZE'});
    } elsif ($h->{'USE'} eq 'First Wort') {
      # calculate at 20 minute addition for First Wort usage
      $hops->{'IBU'} = ibu ($hops->{'Alpha'}, $hops->{'Amount'}, $data->{'SG'}, '20', $data->{'BATCH_SIZE'});
    } else {
      $hops->{'IBU'} = 0;
    }
    $hops->{'sort'} = $hops->{'Time'};

    $data->{'IBU'} += $hops->{'IBU'};
    $data->{'HOPS_WEIGHT'} += $hops->{'Amount'};

    push @{$data->{'HOPS'}}, $hops;
  }

  $data->{'IBUSG'} = $data->{'IBU'} / (($data->{'OG'} - 1) * 1000);

  my $weight = displayUnit ($data->{'HOPS_WEIGHT'}, 'Amount', 'weight');
  my $ibu = displayUnit ($data->{'IBU'}, 'IBU', '') . ' IBU (Tinseth)';
  $data->{'HEADERS'}->{'HOPS'} = [ "Name", "Alpha", "Amount", "Use", "Time", "Form", "IBU" ];
  $data->{'CAPTIONS'}->{'HOPS'} = "Total hops: $weight / $ibu";
}

sub processMisc ($@) {
  my ($data, @misc) = @_;

  my (@boil_h, @primary_h, @secondary_h, @bottling_h);
  foreach my $m (@misc) {
    my $misc;
    $misc->{'Name'} = $m->{'NAME'};
    $misc->{'Amount'} = $m->{'AMOUNT'};
    if ($m->{'AMOUNT_IS_WEIGHT'} eq 'FALSE') {
      $misc->{'amtype'} = 'volume';
    } else {
      $misc->{'amtype'} = 'weight';
    }
    $misc->{'Time'} = $m->{'TIME'};

    if ($m->{'USE'} eq 'Boil') {
      $misc->{'sort'} = $misc->{'Time'};
      push @{$data->{'ADDITIONS'}->{'BOIL'}}, $misc;
    } elsif ($m->{'USE'} eq 'Primary') {
      $misc->{'sort'} = $misc->{'Amount'};
      push @{$data->{'ADDITIONS'}->{'PRIMARY'}}, $misc;
    } elsif ($m->{'USE'} eq 'Secondary') {
      $misc->{'sort'} = $misc->{'Amount'};
      push @{$data->{'ADDITIONS'}->{'SECONDARY'}}, $misc;
    }
  }

  $data->{'HEADERS'}->{'ADDITIONS'}->{'BOIL'} = [ "Name", "Amount", "Time" ];
  $data->{'HEADERS'}->{'ADDITIONS'}->{'PRIMARY'} = [ "Name", "Amount" ];
  $data->{'HEADERS'}->{'ADDITIONS'}->{'SECONDARY'} = [ "Name", "Amount" ];

  $data->{'CAPTIONS'}->{'ADDITIONS'}->{'BOIL'} = "";
  $data->{'CAPTIONS'}->{'ADDITIONS'}->{'PRIMARY'} = "";
  $data->{'CAPTIONS'}->{'ADDITIONS'}->{'SECONDARY'} = "";
}

sub processYeast ($@) {
  my ($data, @yeast) = @_;

  foreach my $y (@yeast) {
    my $yeast;
    $yeast->{'Name'} = $y->{'NAME'};
    $yeast->{'Amount'} = $y->{'AMOUNT'};
    $yeast->{'Form'} = $y->{'FORM'};
    $yeast->{'Source'} = $y->{'LABORATORY'};
    if ($y->{'AMOUNT_IS_WEIGHT'} eq 'FALSE') {
      $yeast->{'amtype'} = 'volume';
    } else {
      $yeast->{'amtype'} = 'weight';
    }
    $yeast->{'Type'} = $y->{'TYPE'};
    $yeast->{'Flocc.'} = $y->{'FLOCCULATION'};
    $yeast->{'Att.'} = $y->{'ATTENUATION'};

    if ($y->{'ADD_TO_SECONDARY'} eq 'FALSE') {
      $yeast->{'Stage'} = 'Primary';
      $yeast->{'sort'} = -1;
    } else {
      $yeast->{'Stage'} = 'Secondary';
      $yeast->{'sort'} = -2;
    }

    push @{$data->{'YEAST'}}, $yeast;
  }

  #$data->{'HEADERS'}->{'YEAST'} = [ "Name", "Type", "Form", "Flocculation", "Attenuation", "Amount", "Stage", ];
  $data->{'HEADERS'}->{'YEAST'} = [ "Name", "Source", "Type", "Form", "Flocc.", "Att.", "Amount", "Stage", ];
  $data->{'CAPTIONS'}->{'YEAST'} = "";
}

sub processMash ($@) {
  my ($data, @mash) = @_;

  my $step = 0;
  my $total_amount = 0;
  my $got_sparge = 0;
  my $sparge_text = '';

  foreach my $m (@mash) {
    if ($m->{'NAME'} =~ /sparge/i) {
      $got_sparge = 1;
      $data->{'SPARGE_AMOUNT'} = $m->{'INFUSE_AMOUNT'};
      $data->{'SPARGE_TEMP'} = $m->{'INFUSE_TEMP'};
    } else {
      my $mash;
      $mash->{'Name'} = $m->{'NAME'};
      $mash->{'Amount'} = $m->{'INFUSE_AMOUNT'};
      $mash->{'amtype'} = 'volume';
      $mash->{'Type'} = $m->{'TYPE'};
      $mash->{'Temp'} = $m->{'INFUSE_TEMP'};
      $mash->{'Target Temp'} = $m->{'STEP_TEMP'};
      $mash->{'Time'} = $m->{'STEP_TIME'};
      $mash->{'sort'} = $step--;
      $total_amount += $mash->{'Amount'};
      push @{$data->{'MASH'}}, $mash;
    }
  }

  if (!$got_sparge) {
    $data->{'SPARGE_AMOUNT'} = $data->{'BOIL_SIZE'} - ($total_amount - 1.01 * $data->{'FERMENTABLES_WEIGHT'});
  }

  my $sparge_amount = volformat ($data->{'SPARGE_AMOUNT'});
  my $sparge_temp = sprintf ("%3.0f F", fahrentemp ($data->{'SPARGE_TEMP'}));

  $data->{'HEADERS'}->{'MASH'} = [ "Name", "Type", "Amount", "Temp", "Target Temp", "Time" ];
  $data->{'CAPTIONS'}->{'MASH'} = "Sparge with $sparge_amount water at $sparge_temp.";
}

sub parseBeerXML ($) {
  my ($recipe) = @_;
  my ($data);

  # Set up general information

  $data->{'NAME'} = $recipe->{'NAME'};
  $data->{'STYLE'} = $recipe->{'STYLE'}->{'NAME'};
  $data->{'STYLE_ID'} = $recipe->{'STYLE'}->{'CATEGORY_NUMBER'} . $recipe->{'STYLE'}->{'STYLE_LETTER'};
  $data->{'TYPE'} = $recipe->{'TYPE'};
  $data->{'BREWER'} = $recipe->{'BREWER'};
  $data->{'STYLE_DATA'} = $recipe->{'STYLE'};

  # Batch/boil size seems to be standard
  $data->{'BATCH_SIZE'} = $recipe->{'BATCH_SIZE'};
  $data->{'BOIL_SIZE'} = $recipe->{'BOIL_SIZE'};
  $data->{'BOIL_TIME'} = $recipe->{'BOIL_TIME'};

  # Parse out measured/estimated
  if (ref ($recipe->{'BREWNOTES'}->{'BREWNOTE'}) eq 'HASH') {
    # Brewtarget's measured info
    $data->{'OG'} = $recipe->{'BREWNOTES'}->{'BREWNOTE'}->{'OG'};
    $data->{'FG'} = $recipe->{'BREWNOTES'}->{'BREWNOTE'}->{'FG'};
    $data->{'SG'} = $recipe->{'BREWNOTES'}->{'BREWNOTE'}->{'SG'};
    $data->{'BOIL_SIZE'} = $recipe->{'BREWNOTES'}->{'BREWNOTE'}->{'VOLUME_INTO_BK'};
    #$data->{'BATCH_SIZE'} = $recipe->{'BREWNOTES'}->{'BREWNOTE'}->{'VOLUME_INTO_FERMENTER'};
    $data->{'BATCH_SIZE'} = $recipe->{'BREWNOTES'}->{'BREWNOTE'}->{'FINAL_VOLUME'};
    my ($y, $m, $d) = (split (/[-T]/, $recipe->{'BREWNOTES'}->{'BREWNOTE'}->{'BREWDATE'}));
    $data->{'DATE'} = "$m/$d/$y";
    # Get notes
    if ($recipe->{'BREWNOTES'}->{'BREWNOTE'}->{'NOTES'} ne '') {
      $data->{'NOTES'} = $recipe->{'BREWNOTES'}->{'BREWNOTE'}->{'NOTES'};
    }
  } else {
    # Figure out if we have measured values
    $data->{'OG'} = ($recipe->{'OG'} != 0) ? $recipe->{'OG'} : $recipe->{'EST_OG'};
    $data->{'FG'} = ($recipe->{'FG'} != 0) ? $recipe->{'FG'} : $recipe->{'EST_FG'};
    $data->{'OG'} =~ s/\s+SG$//;
    $data->{'FG'} =~ s/\s+SG$//;
    $data->{'DATE'} = $recipe->{'DATE'};
  }

  # set up pre-boil SG
  if ($data->{'SG'} eq '') {
    my $ogp = ($data->{'OG'} - 1) * 1000;
    my $sgp = $data->{'BATCH_SIZE'} * $ogp / $data->{'BOIL_SIZE'};
    $data->{'SG'} = $sgp / 1000 + 1;
  }

  # Get notes from BeerSmith
  if (ref ($recipe->{'NOTES'}) eq '') {
    $data->{'NOTES'} = $recipe->{'NOTES'};
  }
  if (ref ($recipe->{'TASTE_NOTES'}) eq '') {
    $data->{'TASTE_NOTES'} = $recipe->{'TASTE_NOTES'};
  }

  # We have enough info to calculate ABV now
  $data->{'ABV'} = abv ($data->{'OG'}, $data->{'FG'});

  # Get the sparge temperature from mash definition
  $data->{'SPARGE_TEMP'} = $recipe->{'MASH'}->{'SPARGE_TEMP'};

  # Run through the ingredients and steps
  my (@ferm, @hops, @yeast, @misc, @mash);
  @ferm = reftype ($recipe->{'FERMENTABLES'}->{'FERMENTABLE'});
  @hops = reftype ($recipe->{'HOPS'}->{'HOP'});
  @misc = reftype ($recipe->{'MISCS'}->{'MISC'});
  @yeast = reftype ($recipe->{'YEASTS'}->{'YEAST'});
  @mash = reftype ($recipe->{'MASH'}->{'MASH_STEPS'}->{'MASH_STEP'});

  # adds FERMENTABLES, FERMENTABLES_WEIGHT, MCU, SRM and caption
  processFermentables ($data, @ferm);

  # adds IBU, HOPS, HOPS_WEIGHT
  processHops ($data, @hops);

  # adds ADDITIONS->BOIL/PRIMARY/SECONDARY/BOTTLING
  processMisc ($data, @misc); # adds {'BOIL_ADD'} and {'PRIMARY_ADD'}

  # adds YEAST
  processYeast ($data, @yeast);

  # adds MASH
  if ($data->{'TYPE'} eq 'All Grain') {
    processMash ($data, @mash);
  }

  return ($data);
}

sub displayUnit ($$$) {
  my ($value, $type, $subtype) = @_;
  my ($display);

  if ($type eq 'Amount') {
    if ($subtype eq 'weight') { $display = kgconvert ($value) }
    if ($subtype eq 'volume') { $display = volformat ($value) }
  } elsif ($type eq 'Alpha' || $type eq 'ABV' || $type eq '%') {
    $display = sprintf ("%2.1f%%", $value);
  } elsif ($type eq 'IBU') {
    $display = sprintf ("%3.1f", $value);
  } elsif ($type eq 'IBU/SG') {
    $display = sprintf ("%1.2f", $value);
  } elsif ($type eq 'Time') {
    if ($value >= 1440) {
      $value = $value / 1440;
      $display = sprintf ("%2.0f day", $value);
    } else {
      $display = sprintf ("%2.0f min", $value);
    }
  } elsif ($type =~ /^(Yield|Att(enuation|\.)?)$/) {
    $display = sprintf ("%2.0f%%", $value);
  } elsif ($type eq 'Color') {
    $display = sprintf ("%3.0f SRM", $value);
  } elsif ($type eq 'MCU') {
    $display = sprintf ("%2.1f", $value);
  } elsif ($type eq 'Gravity') {
    $display = sprintf ("%1.3f", $value);
  } elsif ($type =~ /Temp/) {
    if ($value =~ /^([\d\.]+)\s+F$/) {
      $display = sprintf ("%3.0f F", $1);
    } else {
      $display = sprintf ("%3.0f F", c2f ($value));
    }
  } else {
    $display = $value;
  }

  $display =~ s/^\s+//;
  $display =~ s/\s+$//;

  return ($display);
}

sub textRange ($$$) {
  my ($val, $min, $max) = @_;
  my @range = qw / - - - - - - - - - - - - - - - - - - - - - - - - - /;
  my @low = qw / - - - - - - - - - - /;
  my @high = qw / - - - - - - - - - - /;
  my ($lowtxt, $hightxt, $rangetxt);

  if ($val >= $min && $val <= $max) {
    # in range
    my $pct = ($val - $min) / ($max - $min);
    my $ipct = sprintf ("%3.0f", $pct * (@range - 1));
    $range[$ipct] = '#';
  } else {
    my $range = $max - $min;
    if ($min - $range < 0) {
      $range = $range + ($min - $range);
    }
    if ($val < $min) {
      my $ipct;
      if ($val >= $min - $range) {
        my $pct = ($val - ($min - $range)) / $range;
	$ipct = sprintf ("%3.0f", $pct * (@low - 1));
      } else {
        $ipct = 0;
      }
      $low[$ipct] = '#';
    } else {
      my $ipct;
      if ($val <= $max + $range) {
        my $pct = ($val - $max) / $range;
	$ipct = sprintf ("%3.0f", $pct * (@high - 1));
      } else {
        $ipct = @high - 1;
      }
      $high[$ipct] = '#';
    }
  }

  $rangetxt = join ('', @range);
  $lowtxt = join ('', @low);
  $hightxt = join ('', @high);

  return ('|' . join ('|', $lowtxt, $rangetxt, $hightxt) . '|');
}

sub htmlRange ($$$) {
  my ($val, $min, $max) = @_;
  my @range = qw / - - - - - - - - - - - - - - - - - - - - - - - - - /;
  my @low = qw / - - - - - - - - - - /;
  my @high = qw / - - - - - - - - - - /;
  my ($lowtxt, $hightxt, $rangetxt);

  if ($val >= $min && $val <= $max) {
    # in range
    my $pct = ($val - $min) / ($max - $min);
    my $ipct = sprintf ("%3.0f", $pct * (@range - 1));
    $range[$ipct] = '<font color="green">#</font>';
  } else {
    my $range = $max - $min;
    if ($min - $range < 0) {
      $range = $range + ($min - $range);
    }
    if ($val < $min) {
      my $ipct;
      if ($val >= $min - $range) {
        my $pct = ($val - ($min - $range)) / $range;
	$ipct = sprintf ("%3.0f", $pct * (@low - 1));
      } else {
        $ipct = 0;
      }
      $low[$ipct] = '<font color="red">*</font>';
    } else {
      my $ipct;
      if ($val <= $max + $range) {
        my $pct = ($val - $max) / $range;
	$ipct = sprintf ("%3.0f", $pct * (@high - 1));
      } else {
        $ipct = @high - 1;
      }
      $high[$ipct] = '<font color="red">*</font>';
    }
  }

  $rangetxt = join ('', @range);
  $lowtxt = join ('', @low);
  $hightxt = join ('', @high);

  return ('|' . join ('|', $lowtxt, $rangetxt, $hightxt) . '|');
}

sub htmltable {
  my ($title, $class, $caption, $header, $data) = @_;
  my @data = @{$data};
  my $html = "";

  @data = sort { $b->{'sort'} <=> $a->{'sort'} } @data;

  # start table section, add caption
  $html .= "<h3>$title</h3>\n";
  $html .= "<table id=\"$class\">\n";
  if ($caption ne "") {
    $html .= "  <caption>$caption</caption>\n";
  }

  # start table header
  $html .= "  <tr>\n";
  foreach my $h (@{$header}) {
    $html .= "    <th>$h</th>\n";
  }
  $html .= "  </tr>\n\n";

  # add each table row
  foreach my $d (@data) {
    $html .= "  <tr>\n";
    foreach my $h (@{$header}) {
      my $value = displayUnit ($d->{$h}, $h, $d->{'amtype'});
      $html .= "    <td>$value</td>\n";
    }
    $html .= "  </tr>\n\n";
  }

  $html .= "</table>\n";

  return ($html);
}

sub formatHTML ($) {
  my ($data) = @_;
  my ($html);
  my @sections = qw / FERMENTABLES HOPS ADDITIONS YEAST MASH /;

  # header
  $html = "<html>\n<head>\n<title>$data->{NAME}</title>\n";

  if ($LINKCSS) {
    $html .= "<link rel=\"stylesheet\" type=\"text/css\" href=\"brew.css\" />\n";
  } else {
    my $css = "<style type=\"text/css\">\n";
    open (C, $CSS);
    $css .= join ('', <C>);
    close (C);
    $css .= "</style>\n";
    $html .= $css;
  }

  $html .= "</head>\n<body>\n<div class=\"recipe\">\n";

  # general batch information
  $html .= "<div class=\"general\">\n<div id=\"headerdiv\">\n<table id=\"header\">\n  <caption>$data->{NAME}</caption>\n";
  $html .= "  <tr>\n    <td class=\"label\">Style:</td>\n    <td class=\"value\">";
  $html .= "$data->{STYLE} ($data->{STYLE_ID}) - $data->{TYPE}\n";
  $html .= "    </td>\n  </tr>\n";
  $html .= "  <tr>\n    <td class=\"label\">Date:</td>\n    <td class=\"value\">";
  $html .= $data->{'DATE'} . "\n    </td>\n  </tr>\n";
  $html .= "</table>\n</div>\n";
  $html .= "<div class=\"batch\">\n<table id=\"title\">\n";
  $html .= "  <caption>Batch Description</caption>\n";
  $html .= "  <tr>\n";
  $html .= "    <td class=\"left\">Batch Size</td>\n";
  $html .= "    <td class=\"valuel\">" . volformat ($data->{'BATCH_SIZE'}) . "</td>\n";
  $html .= "    <td class=\"right\">Boil Size</td>\n";
  $html .= "    <td class=\"valuer\">" . volformat ($data->{'BOIL_SIZE'}) . "</td>\n";
  $html .= "  </tr>\n";
  
  $html .= "  <tr>\n";
  $html .= "    <td class=\"left\">Color</td>\n";
  $html .= "    <td class=\"valuel\">" . displayUnit ($data->{'SRM'}, 'Color', '') . " (Morey)</td>\n";
  $html .= "    <td class=\"right\">Boil Time</td>\n";
  $html .= "    <td class=\"valuer\">" . displayUnit ($data->{'BOIL_TIME'}, 'Time', '') . "</td>\n";
  $html .= "  </tr>\n";

  $html .= "  <tr>\n";
  $html .= "    <td class=\"left\">ABV</td>\n";
  $html .= "    <td class=\"valuel\">" . displayUnit ($data->{'ABV'}, 'ABV', '') . "</td>\n";
  $html .= "    <td class=\"right\">SG</td>\n";
  $html .= "    <td class=\"valuer\">" . displayUnit ($data->{'SG'}, 'Gravity', '') . "</td>\n";
  $html .= "  </tr>\n";

  $html .= "  <tr>\n";
  $html .= "    <td class=\"left\">IBU</td>\n";
  $html .= "    <td class=\"valuel\">" . displayUnit ($data->{'IBU'}, 'IBU', '') . " (Tinseth)</td>\n";
  $html .= "    <td class=\"right\">OG</td>\n";
  $html .= "    <td class=\"valuer\">" . displayUnit ($data->{'OG'}, 'Gravity', '') . "</td>\n";
  $html .= "  </tr>\n";

  $html .= "  <tr>\n";
  $html .= "    <td class=\"left\">IBU/SG</td>\n";
  $html .= "    <td class=\"valuel\">" . displayUnit ($data->{'IBUSG'}, 'IBU/SG', '') . "</td>\n";
  $html .= "    <td class=\"right\">FG</td>\n";
  $html .= "    <td class=\"valuer\">" . displayUnit ($data->{'FG'}, 'Gravity', '') . "</td>\n";
  $html .= "  </tr>\n";


  $html .= "</table>\n</div>\n";

  # display range info
  $html .= "<div class=\"batch\">\n";
  $html .= "<table id=\"stylecmp\"><caption>Style Comparison</caption>\n";
  $html .= "<tr><th>Original Gravity: " . displayUnit ($data->{'OG'}, 'Gravity', '') . ' (' . displayUnit ($data->{'STYLE_DATA'}->{'OG_MIN'}, 'Gravity', '') . ' - ' . displayUnit ($data->{'STYLE_DATA'}->{'OG_MAX'}, 'Gravity', '') . ")</th></tr>\n";
  $html .= '<tr><td>' . htmlRange ($data->{'OG'} - 1, $data->{'STYLE_DATA'}->{'OG_MIN'} - 1, $data->{'STYLE_DATA'}->{'OG_MAX'} - 1) . "</td></tr>\n";

  $html .= "<tr><th>Finishing Gravity: " . displayUnit ($data->{'FG'}, 'Gravity', '') . ' (' . displayUnit ($data->{'STYLE_DATA'}->{'FG_MIN'}, 'Gravity', '') . ' - ' . displayUnit ($data->{'STYLE_DATA'}->{'FG_MAX'}, 'Gravity', '') . ")</th></tr>\n";
  $html .= '<tr><td>' . htmlRange ($data->{'FG'} - 1, $data->{'STYLE_DATA'}->{'FG_MIN'} - 1, $data->{'STYLE_DATA'}->{'FG_MAX'} - 1) . "</td></tr>\n";

  $html .= "<tr><th>Color: " . displayUnit ($data->{'SRM'}, 'Color', '') . ' (' . displayUnit ($data->{'STYLE_DATA'}->{'COLOR_MIN'}, 'Color', '') . ' - ' . displayUnit ($data->{'STYLE_DATA'}->{'COLOR_MAX'}, 'Color', '') . ")</th></tr>\n";
  $html .= '<tr><td>' . htmlRange ($data->{'SRM'}, $data->{'STYLE_DATA'}->{'COLOR_MIN'}, $data->{'STYLE_DATA'}->{'COLOR_MAX'}) . "</td></tr>\n";

  $html .= "<tr><th>Alcohol: " . displayUnit ($data->{'ABV'}, 'ABV', '') . ' (' . displayUnit ($data->{'STYLE_DATA'}->{'ABV_MIN'}, 'ABV', '') . ' - ' . displayUnit ($data->{'STYLE_DATA'}->{'ABV_MAX'}, 'ABV', '') . ")</th></tr>\n";
  $html .= '<tr><td>' . htmlRange ($data->{'ABV'}, $data->{'STYLE_DATA'}->{'ABV_MIN'}, $data->{'STYLE_DATA'}->{'ABV_MAX'}) . "</td></tr>\n";

  $html .= "<tr><th>Bitterness: " . displayUnit ($data->{'IBU'}, 'IBU', '') . ' (' . displayUnit ($data->{'STYLE_DATA'}->{'IBU_MIN'}, 'IBU', '') . ' - ' . displayUnit ($data->{'STYLE_DATA'}->{'IBU_MAX'}, 'IBU', '') . ")</th></tr>\n";
  $html .= '<tr><td>' . htmlRange ($data->{'IBU'}, $data->{'STYLE_DATA'}->{'IBU_MIN'}, $data->{'STYLE_DATA'}->{'IBU_MAX'}) . "</td></tr>\n";

  $html .= "</table>\n</div>\n</div>\n";

  foreach my $s (@sections) {
    next if ($data->{'TYPE'} ne 'All Grain' && $s eq 'MASH');
    if ($s eq 'ADDITIONS') {
      foreach my $stage (keys (%{$data->{'ADDITIONS'}})) {
        my $title = ucfirst (lc ($s)) . ' to ' . ucfirst (lc ($stage));
	my $class = lc ($s);
	my $caption = $data->{'CAPTIONS'}->{$s}->{$stage};
	my $header = $data->{'HEADERS'}->{$s}->{$stage};
	my $table = $data->{$s}->{$stage};
        $html .= htmltable ($title, $class, $caption, $header, $table);
      }
    } else {
      my $title = ucfirst (lc ($s));
      my $class = lc ($s);
      my $caption = $data->{'CAPTIONS'}->{$s};
      my $header = $data->{'HEADERS'}->{$s};
      my $table = $data->{$s};
      $html .= htmltable ($title, $class, $caption, $header, $table);
    }
  }

  $html .= "</div>\n</div>\n";

  # Notes

  if ($NOTES) {
    $html .= "<div class=\"notes\">\n";
    if (defined ($data->{'NOTES'}) && $data->{'NOTES'} ne '') {
      $html .= "  <h1>Brew Notes</h1>\n";
      $html .= $data->{'NOTES'} . "\n";
    }
    if (defined ($data->{'TASTE_NOTES'}) && $data->{'TASTE_NOTES'} ne '') {
      $html .= "  <h1>Tasting Notes</h1>\n";
      $html .= $data->{'TASTE_NOTES'} . "\n";
    }
    $html .= "</div>\n";
  }

  $html .= "</body>\n</html>";

  return ($html);
}

sub formatDAT ($) {
  my ($data) = @_;
  my ($output);

  $output = join ('|', $data->{'NAME'}, $data->{'STYLE'} . ' (' . $data->{'TYPE'} . ')', $data->{'DATE'});
  return ($output);
}

sub texttable {
  my ($title, $class, $caption, $header, $data) = @_;
  my @data = @{$data};
  my ($text, @maxwidth, @lines);

  @data = sort { $b->{'sort'} <=> $a->{'sort'} } @data;

  # start table section, add caption
  $text = '-' x 80;
  $text .= "\n$title\n";

  if ($caption ne '') {
    $text .= "$caption\n";
  }

  $text .= "\n";

  # start table header
  my $i = 0;
  foreach my $h (@{$header}) {
    $maxwidth[$i++] = length ($h);
  }
  push @lines, $header;

  # add each table row
  foreach my $d (@data) {
    my @line;
    $i = 0;
    foreach my $h (@{$header}) {
      my $value = displayUnit ($d->{$h}, $h, $d->{'amtype'});
      $maxwidth[$i] = $maxwidth[$i] < length($value) ? length($value) : $maxwidth[$i];
      $i++;
      push @line, $value;
    }
    push @lines, \@line;
  }

  foreach my $l (@lines) {
    $i = 0;
    $text .= '  ';
    foreach my $d (@$l) {
      my $w = $maxwidth[$i++] + 2;
      $text .= sprintf ('%-' . $w . 's', $d);
    }
    $text .= "\n";
  }

  $text .= "\n";

  return ($text);
}

sub formatText ($) {
  my ($data) = @_;
  my ($text);
  my @sections = qw / FERMENTABLES HOPS ADDITIONS YEAST MASH /;

  $text = '-' x 80 . "\n";
  $text .= "Beer: $data->{NAME}\n";
  $text .= "Style: $data->{STYLE} ($data->{STYLE_ID}) - $data->{TYPE}\n";
  $text .= "Brew Date: $data->{DATE}\n";
  $text .= '-' x 80 . "\n";
  $text .= "Batch Description\n\n";
  $text .= sprintf ("    %10s: %-28s %10s: %-10s\n", 'Batch Size', volformat ($data->{'BATCH_SIZE'}), 'Boil Size', volformat ($data->{'BOIL_SIZE'}));
  $text .= sprintf ("    %10s: %-28s %10s: %-10s\n", 'Color', displayUnit ($data->{'SRM'}, 'Color', '') . ' (Morey)', 'Boil Time', displayUnit ($data->{'BOIL_TIME'}, 'Time', ''));
  $text .= sprintf ("    %10s: %-28s %10s: %-10s\n", 'ABV', displayUnit ($data->{'ABV'}, 'ABV', ''), 'SG', displayUnit ($data->{'SG'}, 'Gravity', ''));
  $text .= sprintf ("    %10s: %-28s %10s: %-10s\n", 'IBU', displayUnit ($data->{'IBU'}, 'IBU', '') . ' (Tinseth)', 'OG', displayUnit ($data->{'OG'}, 'Gravity', ''));
  $text .= sprintf ("    %10s: %-28s %10s: %-10s\n", 'IBU/SG', displayUnit ($data->{'IBUSG'}, 'IBU/SG', ''), 'FG', displayUnit ($data->{'FG'}, 'Gravity', ''));

  $text .= "\n";

  # display range info
  $text .= "    Style Comparison\n\n";
  $text .= "        Original Gravity: " . displayUnit ($data->{'OG'}, 'Gravity', '') . ' (' . displayUnit ($data->{'STYLE_DATA'}->{'OG_MIN'}, 'Gravity', '') . ' - ' . displayUnit ($data->{'STYLE_DATA'}->{'OG_MAX'}, 'Gravity', '') . ")\n";
  $text .= '        ' . textRange ($data->{'OG'} - 1, $data->{'STYLE_DATA'}->{'OG_MIN'} - 1, $data->{'STYLE_DATA'}->{'OG_MAX'} - 1) . "\n";

  $text .= "        Finishing Gravity: " . displayUnit ($data->{'FG'}, 'Gravity', '') . ' (' . displayUnit ($data->{'STYLE_DATA'}->{'FG_MIN'}, 'Gravity', '') . ' - ' . displayUnit ($data->{'STYLE_DATA'}->{'FG_MAX'}, 'Gravity', '') . ")\n";
  $text .= '        ' . textRange ($data->{'FG'} - 1, $data->{'STYLE_DATA'}->{'FG_MIN'} - 1, $data->{'STYLE_DATA'}->{'FG_MAX'} - 1) . "\n";

  $text .= "        Color: " . displayUnit ($data->{'SRM'}, 'Color', '') . ' (' . displayUnit ($data->{'STYLE_DATA'}->{'COLOR_MIN'}, 'Color', '') . ' - ' . displayUnit ($data->{'STYLE_DATA'}->{'COLOR_MAX'}, 'Color', '') . ")\n";
  $text .= '        ' . textRange ($data->{'SRM'}, $data->{'STYLE_DATA'}->{'COLOR_MIN'}, $data->{'STYLE_DATA'}->{'COLOR_MAX'}) . "\n";

  $text .= "        Alcohol: " . displayUnit ($data->{'ABV'}, 'ABV', '') . ' (' . displayUnit ($data->{'STYLE_DATA'}->{'ABV_MIN'}, 'ABV', '') . ' - ' . displayUnit ($data->{'STYLE_DATA'}->{'ABV_MAX'}, 'ABV', '') . ")\n";
  $text .= '        ' . textRange ($data->{'ABV'}, $data->{'STYLE_DATA'}->{'ABV_MIN'}, $data->{'STYLE_DATA'}->{'ABV_MAX'}) . "\n";

  $text .= "        Bitterness: " . displayUnit ($data->{'IBU'}, 'IBU', '') . ' (' . displayUnit ($data->{'STYLE_DATA'}->{'IBU_MIN'}, 'IBU', '') . ' - ' . displayUnit ($data->{'STYLE_DATA'}->{'IBU_MAX'}, 'IBU', '') . ")\n";
  $text .= '        ' . textRange ($data->{'IBU'}, $data->{'STYLE_DATA'}->{'IBU_MIN'}, $data->{'STYLE_DATA'}->{'IBU_MAX'}) . "\n";

  $text .= "\n";

  foreach my $s (@sections) {
    next if ($data->{'TYPE'} ne 'All Grain' && $s eq 'MASH');
    if ($s eq 'ADDITIONS') {
      foreach my $stage (keys (%{$data->{'ADDITIONS'}})) {
        my $title = ucfirst (lc ($s)) . ' to ' . ucfirst (lc ($stage));
        my $class = lc ($s);
        my $caption = $data->{'CAPTIONS'}->{$s}->{$stage};
        my $header = $data->{'HEADERS'}->{$s}->{$stage};
        my $table = $data->{$s}->{$stage};
        $text .= texttable ($title, $class, $caption, $header, $table);
      }
    } else {
      my $title = ucfirst (lc ($s));
      my $class = lc ($s);
      my $caption = $data->{'CAPTIONS'}->{$s};
      my $header = $data->{'HEADERS'}->{$s};
      my $table = $data->{$s};
      $text .= texttable ($title, $class, $caption, $header, $table);
    }
  }

  if ($NOTES) {
    $Text::Wrap::columns = 72;
    if (defined ($data->{'NOTES'}) && $data->{'NOTES'} ne '') {
      $text .= '-' x 80 . "\n";
      $text .= "Brew Notes\n\n";
      $text .= wrap ('', '', $data->{'NOTES'});
      $text .= "\n";
    }
    if (defined ($data->{'TASTE_NOTES'}) && $data->{'TASTE_NOTES'} ne '') {
      $text .= '-' x 80 . "\n";
      $text .= "Tasting Notes\n\n";
      $text .= wrap ('', '', $data->{'TASTE_NOTES'});
      $text .= "\n";
    }
  }

  $text .= '-' x 80 . "\n";

  return ($text);
}

MAIN:
{
  my ($xml, %opts, $format);
  getopts ('c:f:lno:t', \%opts);
  if (defined ($opts{'f'})) {
    $format = $opts{'f'};
  } else {
    $format = 'html';
  }

  ($opts{'c'}) && ($CSS = $opts{'c'});
  ($opts{'l'}) && ($LINKCSS = 1);
  ($opts{'n'}) && ($NOTES = 1);

  foreach my $filename (@ARGV) {

    # read BeerXML contents
    open (F, $filename);
    my $file = join ('', <F>);
    close (F);

    # Correct Brewtarget's invalid XML encoding value, if present
    $file =~ s/encoding="System"/encoding="UTF-8"/;

    # Determine output file name
    my $outfile;
    if ($opts{'o'}) {
      $outfile = $opts{'o'};
    } else {
      $outfile = $filename;
      $outfile =~ s/\.xml$/\.html/;
    }

    # Parse XML
    $xml = XMLin ($file, KeepRoot => 1);

    # Massage input
    my $recipe = parseBeerXML ($xml->{'RECIPES'}->{'RECIPE'});

    # Format output
    my $output;
    if ($format eq 'html') {
      $output = formatHTML ($recipe);
      print "$output\n";
    } elsif ($format eq 'text') {
      $output = formatText ($recipe);
      print $output;
    } elsif ($format eq 'dat') {
      $output = formatDAT ($recipe);
      print "$outfile|$output\n";
    } else {
      print Dumper $recipe;
    }
  }
}
