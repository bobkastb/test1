param( $p_stady , [alias("get","g")][switch]$in_getdata   )
$g__DebugInternal=$null;
#$g__DebugInternal=1
$ScriptDir = [IO.Path]::GetFullPath($($MyInvocation.MyCommand.Definition | split-path -parent));
#$basedatadir="d:\disks\skydrive\work\bots\crisis\bots\data\stat1\";
$basedatadir="D:\Temp\bot\crisis\stat";
#$basedatadir="D:\Temp\bot\crisis\stat\arch\0103\";
if (![io.directory]::exists($basedatadir)) { $basedatadir=$env:temp+'crisis\stat' };
[System.Globalization.NumberFormatInfo]::CurrentInfo.NumberDecimalSeparator='.';

$config=@{
	wrstady=[int]$p_stady;
	logonstr= get-content "$ScriptDir\public-login.txt" | select -first 1;
	tournamenttype="clan_pvp_tournament";
	resultdir="$basedatadir";
	userinfodir="$basedatadir\users";
	f_users="$basedatadir\users.list.txt";
    f_battles="$basedatadir\battles.arr.txt";
	report_template=get-content "$ScriptDir\stat_report_template.txt" | out-string;
	outdir="\\bot-pc\dropbox\crisis\stat\kv";
	
	detfields='final_strange_item:2,strength_item:2,winpercent_current:2,games_current:5,winpercent_total:2,games_total:5,userid:23,experience:5,gold_overall_real:5,honor:5,rating:5,strange_item:2,strange_mutagen_item:2';
	fields='ДСЛ ФС СЛ WCurr:7 WAll:7 user:23 exp:5 gold:5 honor:5 rate:5 ЛГ МЛ';
};
$ctx=@{
	date='07.03.2016' -as [datetime];
	clans=@{};
	clanworklist=@();
	hcnt=0; u_hcnt=0; u_err=0;
	badbattle=0;
	battles=@{};  # clans=los,win; ulos=user1,user2..; uwin=user1,user2..
	battl_list=@();

	l_blist=@();
	
	f_users="$($config.resultdir)\users.list.txt";
    f_battles="$($config.resultdir)\battles.arr.txt";

};


function decode_base64($s) {  if (!$encUTF8) { $global:encUTF8= new-object Text.UTF8Encoding;} $encUTF8.getstring([convert]::FromBase64String($s) ); };
function get_dt($d) { ('01.01.1970' -as [datetime]) + (new-object timespan(0,3,[int]$d,0));}; # будет время по Москве
function exfn($fn) { $null=$fn -match '(?<n>.+)\.xml$'; $matches.n; }
function idiv( $v , $d) { [math]::Truncate( $v/$d );}		
function formatpercent($p) {'{0:D2}%' -f [int]$p; }
function idiv( $v , $d) { [math]::Truncate( $v/$d );}
function getOrNew_field( $lst , $nm , $init ) { $r=$lst[$nm]; if (!$r) { $r=$lst[$nm]=. $init}; return $r; }
function print_ht( $hta , $fields ) { 	$hta | % { new-object PSObject -Property $_} | ft -AutoSize -Property $sflds |  out-string };
function global:ConvertTo-Json20([object] $item){
    add-type -assembly system.web.extensions
    $ps_js=new-object system.web.script.serialization.javascriptSerializer
	$ps_js.MaxJsonLength=16*1024*1024;
    return $ps_js.Serialize($item)
}


function doPost( $data) {
	$fmsk = '^\<(?<nm>\w+) *\>';
	if (!($data -match $fmsk)) { throw 'bad query'}
	$cmd=$matches.nm; 
	$uri= "http://game-r03ww.rjgplay.com/command/$cmd";
	$data = $data -replace $fmsk,("<$cmd $($config.logonstr)>" );
	
	if (!($client= $config.Channel)) { $client= $config.Channel= new-object System.Net.WebClient;	}
	$client.Headers.Add("Content-Type", "application/xml; charset=utf-8"); 
	$client.Encoding = [System.Text.Encoding]::UTF8;
	#doLog $MLVL_POST "post:$uri -->> $data" -Color Blue
	#write-host "post:$uri -->> $data" -f Blue
	if ($config.DebugInternal) { return '' };
	$t= $client.UploadString($uri, $data ); 
	if ($t -match '<internal_error>') { throw "error upload! on $data" }
	return $t;
}

$crlf='
';

function flushdata( $arr , $nmid , [switch]$flush ) {
	if ( ($arr.count % 100) -ne 0) { return; }
	write-host "flush $nmid" -f green
	$r= getOrNew_field $ctx "r_$nmid" {@{}};
	if (!$r.file) { $r.file="{0}\{1}.arr.txt" -f $config.resultdir,$nmid; }
	if (!$r.first) { $r.first=0; [io.file]::delete( $r.file ) };
	($arr[$r.first..$arr.count] | %{ $_.text }) -join $crlf | out-file $r.file -encoding 'utf8' -append;
	$r.first = $arr.count;
};


function addclan( $clan_id , [switch]$noflush) { 
    if ($ctx.clans.contains($clan_id)) { return; };
	#write-host "added clan $clan_id"
	$c=$ctx.clans[$clan_id]=@{id=$clan_id}; 
	$ctx.clanworklist += $c; 
	$c.text=$c.id ;
	if (!$noflush) { flushdata $ctx.clanworklist "clans" }
	return 1;
	
}
function add_battle( $bat ){
	if ( $ctx.battles.contains($bat.key) ) { return; }
	$ctx.battles[$bat.key] = $bat;
	$ctx.battl_list += $bat;
	flushdata $ctx.battl_list "battles";
	return 1;
}

function getstartclanlist(  ) {
  $t=doPost "<get_clan_tournament_info>  <type>$($config.tournamenttype)</type> </get_clan_tournament_info>";
  $x=[xml]$t;
  foreach ($xc in $x.response.clan_tournament_info.top.ChildNodes)  { if ($id=$xc.clan_id) { $null=addclan $id -noflush; } };
}
function get_user_info($uid){ doPost "<get_user_info><user>$uid</user></get_user_info>"; }
function get_clan_history( $clan_id ) { dopost ("<get_clan_tournament_history> <world_id>ru</world_id><clan_id>{0}</clan_id><type>{1}</type></get_clan_tournament_history>" -f $clan_id,$config.tournamenttype); }
function get_user_profile($uid){ doPost "<get_user_profile><uid>$uid</uid></get_user_profile>" };

function statfor_clan( $crec ) {
  $t=get_clan_history $crec.id; 
  $x=[xml]$t;
  write-host "handle clan $($crec.id)" -f blue;
  function getuids( $bc ) { $(foreach ($u in $bc.ChildNodes) { [string]$u.uid }) | sort };
  foreach ($st in $x.response.clan_tournament_history.stages.ChildNodes) {
	foreach ($b in $st.ChildNodes) {
		$bat=@{ time=[int]$st.start_time; win=$null; loss=$null; key=''; cntc=0;}
		$newc = 0;
		foreach ($bc in $b.ChildNodes) { 
			$c=@{ clan=$bc.clan_id; u= [array](getuids $bc); };
			if ($c.clan -eq $b.winner_clan) { $bat.win=$c; } else {$bat.loss=$c;}
			$bat.cntc ++;
			$newc += [int](addclan $c.clan);
			#($c.u -join ';') | out-host;
		}; 
		if (!$b.winner_clan) { write-host 'battle in continue!' -f red; $ctx.badbattle++; break; }
		if (($bat.cntc -ne 2) -or (!$bat.win) -or (!$bat.loss)) { $bat | out-host; throw "winner not found $($b.winner_clan)  cnt=$($bat.cntc) " };
		$bat.key='{0} {1}' -f $bat.time,$bat.win.u[0];
		#$bat.key | out-host; write-host $bat.win.u.gettype() ;  throw 'stop';
		$bat.text="$($bat.time) | " + (( $bat.win,$bat.loss |%{  "$($_.clan) $($_.u)" } ) -join ' | ');   
		$newb=add_battle $bat;
		if ($newc -and !$newb) { 
			#$bat.key , $bat.text, $ctx.battles[$bat.key].text | out-host;			write-host $t  -f cyan;		$bat.win.u | out-host;
			throw "not a battle at new clan" };
	};
  };
}

function printstat($s) { $host.UI.RawUI.WindowTitle= $s; }

function startlist(){
	$config.resultdir, $config.userinfodir | %{ [IO.Directory]::CreateDirectory($_); };

	getstartclanlist;
	#$ctx.clanworklist = [array]$ctx.clans.values; 
	$ctx.hcnt=0;
	while ($ctx.hcnt -lt $ctx.clanworklist.count) { statfor_clan $ctx.clanworklist[$ctx.hcnt]; $ctx.hcnt++;
		printstat ('clan get battles. {0} from {1} battles {2} bad {3}' -f $ctx.hcnt,$ctx.clanworklist.count,$ctx.battl_list.count,$ctx.badbattle);
	}
	flushdata $ctx.clanworklist "clans" -flush;
	flushdata $ctx.battl_list "battles" -flush;
	$ctx.battles.keys | select -first 10 | out-host;
};
function read_battle_list() {
		if ($ctx.battl_list) { return $ctx.battl_list };	
		write-host 'read_battle_list'
		$dall = get-content $config.f_battles; # | select -first 2;
		write-host 'loaded!'
		$bar= $dall | %{ $a=$_.trim() -split '[\| ]+'; $uc=($a.count-3)/2; $lsst=2+$uc;	@{ time=[int]$a[0]; win=@{ clan=$a[1]; u=$a[2..(2+$uc-1)]}; loss=@{ clan=$a[$lsst]; u=$a[($lsst+1)..($lsst+$uc)]};  } }
		write-host 'handled!'
		$ctx.battl_list=$bar;
		$bar;
}
function read_clanlist() {
	if (!$ctx.clanworklist) { $ctx.clanworklist = get-content "$basedatadir\clans.arr.txt"; };
	$ctx.clanworklist;
};	

function h_ready_battles() {
	$bar= read_battle_list; 
	$ctx.users=@{}; $ctx.usersa=@();
	$ctx.usersa = $bar | %{ $_.win.u; $_.loss.u; } | group -noelement | %{ $_.name } ;#| sort ;
	write-host ('All users {0}' -f $ctx.usersa.count);
	$ctx.usersa -join $crlf | out-file  $config.f_users -encoding 'utf8';
}


function read_user_list() {
		if ($ctx.users.count) { $ctx.users };	
		$ctx.users=@{};
		$dall = get-content "$basedatadir\users.rec.txt" ; # | select -first 2;
		write-host 'loaded users.rec!'
		$dall | %{ $a=$_.trim() -split '\s+'; $ctx.users[$a[1]] = @{ league=$a[0]; uid=$a[1]; clan=$a[2] } };
		write-host 'handled users.rec!'
		$ctx.users
}


function h_getinfo_users() {
	if (!$ctx.usersa) {  
		$ctx.usersa=get-content $config.f_users; 
	}
	$ctx.u_hcnt = 0;	$ctx.users=@{};
	function urec2txt( $u ) { ($u.league,$u.uid,$u.clan,$u.uname| %{ if (!$_) {'*'} else {$_} }) -join '	' }
	function decode_s($a) { $r=if (!$a) { '*' } else {decode_base64 $a};  $r -replace '^\s*$','*' }
	function handleuser_profile($uid,$t_pr) { 
		$x=([xml]$t_pr).response.profile; if (!$x) { $ctx.u_err++; return; };
		$un=$x.params.first_name,$x.params.last_name | %{ decode_s $_ };
		$xuseasons= ($x.seasons.ChildNodes | where {$_.type -eq "user_season"} | select -first 1);
		$res=$ctx.users[$x.uid]=@{ uid=$x.uid; clan=$x.clan_id; league=$xuseasons.league_type; uname='{0} {1}' -f $un  };
		$ctx.u_hcnt++;
		if (($ctx.u_hcnt % 10) -eq 0) {
			printstat ("users: всего {0} обработано {1} ошибок {2}" -f  $ctx.usersa.count,$ctx.u_hcnt,$ctx.u_err); };
		#write-host ('{0} {1}' -f $uid,$res.league)
	}
	write-host 'start get users rec..';
	foreach ($uid in $ctx.usersa) { $t=get_user_profile $uid; handleuser_profile $uid $t; };	
	write-host 'saved users rec..';
	$ctx.users.values |sort {$_.league} | %{ urec2txt $_ } | out-file -encoding 'utf8' "$basedatadir\users.rec.txt";	
};

$league_index=@{ elite=5; gold=4; silver=3; bronze=2 ; recruit=1; ''='e'; };
$league_rusnames='Ошибка','Новобранцы',"Бронза","Серебро","Золото","Элита";
function group2ht($g) { @{ count=$g.count; name=$g.name; group=$g.group } }
function summ( $list , $exp ) { $sm=0; $list | %{ $sm += . $exp; }; $sm; }
function array2columns($a,$incol=10,$sep='   ') { 
	$col=idiv $a.count $incol;  $da=@(); 
	for ($i=0;$i -lt $incol;$i++) {$da+='';}; 
	$c=0; $a | %{ $da[$c]+= '{0}{1}' -f $_,$sep; $c=($c+1) % $incol; };  
	$da; }
function printtimelist( $tl ) {
	$bpa_hlp= 1,2,3 | %{ $s=''; for($k=0;$k -lt $_;$k++) { $s+='<лига>' }; "#Бои $_*$_ <количество боев> $s:$s";  }
	
	$s= $tl |%{ $tv=$_;
        $bbgr= ($tv.group_i | %{ $_.count_all }) -join ' ';
		$tvs=$tv.group_i | %{   
			$a=$_.list | sort {$_.name} |  %{ "{0,3} {1}" -f $_.count,$_.name }; 
			$bpa_hlp[ $_.gr_size - 1 ];	
			' ';
			array2columns $a;
		};
		$tv.headstr
		$tvs;
	}; 
	$s -join $crlf;
	#$s -join $crlf | out-file -encoding utf8
};

function gr2txt($name) {  "<$name>"  };

function outres_json(){
	
	write-host 'out json'
	$ctx.conv_ul_j=$ctx.conv_ul| %{ ,@($_.league,$_.count) }
	$ctx.based_battle_list_j=$ctx.based_battle_list | %{ ,@( $_.percent,$_.nmbattle,$_.count) };
	$ctx.conv_battle_arr_j= $ctx.conv_battle_arr | %{ ,@($_.nmbattle,$_.count) };
	
	$jst=@{	};
	#$jst.conv_ul_j=($ctx.conv_ul| %{ '	"{0}",{1}' -f $_.league,$_.count }) -join ",$crlf";
	#$jst.GroupFromClans=(($ctx.gr_users_j | @{ se= $_.enemies | %{ '[ "{2}",{0,4},{1:F3}]' -f $_.c,$_.v,$_.k }) -join ', ';  '  {{ "group":"{0}", "victory_prob":{1:F3}, "enemies":[{0}] }}' -f $_.ugroup,$_.victory_prob,se }) -join ",$crlf"
	
	$ctx.jsonres=@{
		CountAtTheDay=$ctx.gstat;
		BattlesByGroupSize=$ctx.BattlesByGroupSize;
		leagues_distribution=$ctx.conv_ul_j;
		GroupFromClans=$ctx.gr_users_j;
		based_battle_list=$ctx.based_battle_list_j;
		#based_battle_list_help="percent , group:group , count ";
		convolution_battles=$ctx.conv_battle_arr_j;
		#convolution_battles_help=" group:group , count  ";
	};
	ConvertTo-Json20 $ctx.jsonres | out-file "$basedatadir\report.json" -encoding utf8;
    #$ExecutionContext.InvokeCommand.ExpandString( $config.report_template ) | out-file "$basedatadir\report.txt" -encoding utf8;

}
function h_calcstat() {
	$null= read_user_list; 
	$null= read_battle_list;
	$null=read_clanlist;
	function convolution_league() { write-host 'conv league';	
		$ctx.conv_ul= $ctx.users.values | group {$_.league} | sort { $league_index[$_.name] } | %{ @{count=$_.count;league=$league_rusnames[$league_index[$_.name]] } }; 
		$ctx.conv_ul_text = $ctx.conv_ul| %{ '{0,-20} {1}' -f $_.league,$_.count } | out-string;
		} 
	function get_1( $p ) { ($p.u | %{ $league_index[[string]($ctx.users[$_].league)] } | sort {$_} ) -join '' }
	function slistfield( $hta , $f) { ($hta | %{ $_.$f }) -join ' '; }
	function s_time($time) { $time,(get_dt $time).tostring('HH:mm') -join '  ' }
	function gr_conv1( $g1 , $g2 , $cnt ) { $c=getOrNew_field $ctx.gr_users $g1 {@{ p=@{} }}; $c.p.$g2 += $cnt; $c.all+=$cnt; }
	function gr_conv( $g1 , $g2 , $cnt ) { gr_conv1 $g1 $g2 $cnt; if ($g1 -ne $g2) { gr_conv1 $g2 $g1 $cnt; } }
	function gr_print( $gr ,$k) { 
		function calcpower($k) { $r=0; for ($i=0;$i -lt $k.length;$i++) { $r+= [int]$k[$i]-[int][char]'0' }; $r; }
		function calc_prob($p1,$p2,$cnt) { $v=0.5 + ($p1-$p2)*0.25; $v=if ($v -gt 1) {1} elseif ($v -lt 0) {0} else {$v};  $v*$cnt/$gr.all;  };
        $fa= $gr.p.keys | %{@{v=$gr.p.$_; k="$_";}};
		$jr=@{ ugroup="$k"; victory_prob=0; enemies=@(); };
		$jr.enemies = $fa | sort {-$_.v} | %{ @{c=$_.v; p=($_.v/$gr.all); g=$_.k} };
		#$s = ( $fa | sort {-$_.v} | %{  "{0} {1:F3} {2}" -f $_.v,($_.v/$gr.all),(gr2txt $_.k) ;}) -join ', ';  
		$s= ($jr.enemies | %{ "{0} {1:F3} {2}" -f $_.c,$_.p,$_.g }) -join ', ';  
		$vp=0; $power= calcpower $k; $fa | %{ $pp=calcpower $_.k; $vp+=calc_prob $power $pp $_.v };
		$jr.victory_prob=$vp;
		#$ctx.gr_users_j+=$jr; 
        $ctx.gr_users_j+=@{ ugroup="$k"; victory_prob=$vp; enemies=$jr.enemies; }; 
		'{0:F2}	|| {1}' -f $vp,$s;
	};
	$ctx.date = (get_dt $ctx.battl_list[0].time);
	$ctx.gstat=@{ Users=$ctx.users.count; Battles=$ctx.battl_list.count; Clans= $ctx.clanworklist.count; Date=$ctx.date.tostring('dd.MM.yyyy'); };
	
	convolution_league; $ctx.conv_ul_text | out-host;
	$ctx.gstat.text= "Всего за день:  Users={0} Battles={1}; Clans={2} $crlf" -f $ctx.gstat.users,$ctx.gstat.battles,$ctx.gstat.clans;	
	write-host ('recalc battle {0}' -f $ctx.battl_list.count);
		$l_blist=$ctx.battl_list | %{  $r=@{ time=$_.time; gr_size=$_.win.u.count; gr= (get_1 $_.win) , (get_1 $_.loss); };  	$r.al_a=  $r.gr | sort; $r.al_s=$r.al_a -join ':'; $r; }
	write-host 'based convolution battle ';
		$ctx.conv_battle_arr=$l_blist | group {$_.al_s} | sort {$_.name.length},{$_.name}  | %{ $f=$_.group[0]; @{ Count=$_.count; nmbattle=$_.name; gr_size=$f.gr_size; grnms=$_.name -split ':'; } }
	write-host 'conv time';
		$ctx.time_list= $l_blist | group {$_.time} | sort {$_.name}| %{ @{ time=$_.name; count=$_.count; group=$_.group } };
	write-host 'conv group ...'; $ctx.gr_users=@{};
		#$l_blist | group {$_.gr[0]},{$_.gr[1]} |%{  $n=$_.name -split ', '; gr_conv $n[0] $n[1] $_.count;  } 
		$ctx.conv_battle_arr | %{  gr_conv $_.grnms[0] $_.grnms[1] $_.count;  } 
		$ctx.gr_users_j=@();
		$ctx.gr_users_text= $ctx.gr_users.keys | sort {$_.length},{$_} | %{ '{0} = {1}' -f (gr2txt $_),(gr_print $ctx.gr_users.$_ $_)   } | out-string;
		# BattlesByGroupSize
		$ba=@(0,0,0,0); $ctx.conv_battle_arr | %{ $ba[$_.gr_size] += $_.count; }; $i=1; $ctx.BattlesByGroupSize= $ba[1..10] | %{ @{ grsz=$i; c=[int]$_; p=[int]($_*100/$ctx.gstat.battles) }; $i++; };
		$ctx.text_bbgsz= $ctx.BattlesByGroupSize | %{ '	{0}*{0}	{1}	{2}%' -f $_.grsz,$_.c,$_.p } |out-string;
	write-host 'conv battle ...'; 
		$ctx.conv_battle_text =array2columns ( $ctx.conv_battle_arr| %{ '{0,4} {1,-9}' -f $_.count,(gr2txt $_.nmbattle)}) -incol 30  | out-string ;
		$sp=$ctx.gstat.battles*0.9; 
		$ctx.based_battle_list= $ctx.conv_battle_arr | sort {-$_.count} |where {$sp -gt 0} | %{ $sp-=$_.count; @{ Percent=[int]($_.count*100/$ctx.gstat.battles); nmbattle=$_.nmbattle; count=$_.count} };
		$ctx.based_battle_text= $ctx.based_battle_list | %{ '{0:D2}%  {1,9}  {2}' -f $_.percent,(gr2txt $_.nmbattle),$_.count } | out-string
		
		
	write-host 'time details ...';
	foreach ($tv in $ctx.time_list) {
		$tv.group_al= $tv.group | group { $_.al_s }; # count,name 
		$tv.group_i= $tv.group_al | group { $_.name.length } | sort {$_.name} | %{ @{ gr_size=(([int]$_.name)-1)/2; count_pair= $_.count; list=$_.group; count_all = summ $_.group {$_.count}; } };
		$tv.userscount= summ $tv.group_i { $_.gr_size * $_.count_all * 2 }; 
		$tv.battlescount=$tv.group.count;
		$tv.headstr= "#---------{0} users={1} battles {2} ({3})--------" -f  (s_time $tv.time),$tv.userscount,$tv.battlescount,(slistfield $tv.group_i count_all)
		write-host $tv.headstr;
		#$tv.groupL=@(@(),@(),@());	1,2,3 | %{ $i=$_; $tv.groupL[$i]= $tv.group | group { $_.al_s }; # count,name 
	};
	$ctx.gstat.text,'#-- Распределение персонажей по лигам --',$ctx.conv_ul_text,(printtimelist $ctx.time_list)| out-file "$basedatadir\report-1.txt" -encoding utf8;
    $ExecutionContext.InvokeCommand.ExpandString( $config.report_template ) | out-file "$basedatadir\report.txt" -encoding utf8;
	outres_json;

	
};
#get_clan_history 'a4e1bdf126e02a173ce4aa4d6dabb361'; return;
#function definedate() {}
function ReconnectFtp() {
	$ctx.outserver = New-Object System.Net.WebClient 
	$ctx.outserver.credentials = New-Object System.Net.NetworkCredential("a9032487","RapCrisis");
	$ctx.baseouturl ="ftp://autocrisis.comxa.com/public_html/crisis/kv.stat/";
}	
function out_upload( $f , $relpath , [switch]$asstr) {
	$fnm= if ($asstr) {'!str!'} else { $f};
	write-host "upload $relpath from $fnm" -f cyan; 
	if ($asstr) { $ctx.outserver.uploadstring( ($ctx.baseouturl+$relpath) , $f );
	} else { $ctx.outserver.uploadfile( ($ctx.baseouturl+$relpath) , $f ); }
};	
function out_download(  $relpath ) {    $ctx.outserver.downloadstring( $ctx.baseouturl+$relpath ); 	};
function copy_files(){
	#ftp://autocrisis.comxa.com/public_html/crisis/kv.stat/
	function copyfile( $s , $d) { 	write-host "copy '$s' -> '$d'" -f cyan; 	[IO.File]::Copy( $s , $d , 1 ); }
	function dooutf( $s , $dp ) { out_upload $s $dp;  }
	function dooutrep( $f ) { $d1=$f -replace '\.',".$fdtnm."; 	out_upload "$basedatadir\$f" $f; out_upload "$basedatadir\$f" "reports/$d1"; }
	$fdtnm=  $ctx.date.tostring('yyyyMMdd');
	#$ctx.date,$fdtnm| out-host; return;
	ReconnectFtp;
	"report.txt","report.json" | %{ dooutrep $_; };
	
	$s=out_download 'index.report.txt'; 
	$adstr="reports/report.$fdtnm.json";
	if (!$s.contains($adstr)) {
		$s+=$crlf+$adstr;
		out_upload $s 'index.report.txt' -asstr;
	};	
	
	#$out=$config.outdir;
	#"report.txt","report.json" | %{ copyfile "$basedatadir\$_" "$out\$_" }
	#"report.txt","report.json" | %{ copyfile "$basedatadir\$_" ("$out\reports\{0}" -f ($_ -replace '\.',".$fdtnm.") ) };
	#$d=get-childitem "$out\reports\report*.json"
	#$d | %{ $_.name } | out-file "$out\report.index.txt" -encoding utf8
	
};

function data_get() {
	startlist;
	h_ready_battles;
	h_getinfo_users;
	$ctx.date = (get_dt $ctx.battl_list[0].time);
}


if (0 -ge $config.wrstady ) {
	data_get;
};
if (1 -ge $config.wrstady) {
	h_calcstat;
}
if (2 -ge $config.wrstady) {
	copy_files;
}


