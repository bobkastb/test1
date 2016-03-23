$g__DebugInternal=$null;
#$g__DebugInternal=1;
$ScriptDir=[IO.Path]::GetFullPath($($MyInvocation.MyCommand.Definition | split-path -parent));
$BaseDirectory = [IO.Path]::GetFullPath($ScriptDir+'\..');
$def_data_dir ="d:\temp\bot\crisis"

$config=@{
	current=@{ 	ids=@{ uid=''; auth_key=''; };	};
	websetting=@{ 
		'Content-Type' = "application/xml; charset=utf-8"; 
		Encoding = [System.Text.Encoding]::UTF8;
	};
	DebugInternal = $g__DebugInternal;
	dirs=@{
		userdata="$def_data_dir\data";
		aliendata="$def_data_dir\alien";
		logs="$def_data_dir\logs";
		cashe="$def_data_dir\cashe";
	};
	files=@{ 
		ubattlelog={ $config.dirs.logs+'\ubattle.log.txt' };
		saved_gc={ "{0}\{1}.xml" -f $config.dirs.userdata,(getcurrent_userkey) };
		last_battles_cache= { "{0}\lastbattlekey.{1}.xml" -f $config.dirs.cashe,(getcurrent_userkey) };
	};
}

function prepConfig() {
	$config.dirs.values | %{[IO.Directory]::CreateDirectory($_)} | out-null;
}

function idiv( $v , $d) { if ($d) { [math]::Truncate( $v/$d ); } else { 0 } }		
function  get_context() { $config.current }
function id2key($id) { $id -replace ':','-'};
function getcurrent_userkey() { id2key $config.current.ids.uid };
function getSavedXmlDataFileName() { . $config.files.saved_gc;}
function get_dt($d) { [datetime]'01.01.1970' + (new-object timespan(0,0,0,[int]$d));	};# секунды с 01.01.1970 


function doPost(  $uri , $data) {
	if (!($client= $config.Channel)) { $client= $config.Channel= new-object System.Net.WebClient;	}
	$client.Headers.Add("Content-Type", $config.websetting['Content-Type']); 
	$client.Encoding = $config.websetting.Encoding; 
	#doLog $MLVL_POST "post:$uri -->> $data" -Color Blue
	write-host "post:$uri -->> $data" -f Blue
	if ($config.DebugInternal) { return '' };
	$t= $client.UploadString($uri, $data ); 
	return $t;
}

function doPostCMD(   $data) {
	if (!($data -match '^\<(?<nm>\w+) ')) { throw 'bad query'}
	$cmd=$matches.nm; 
	$uri=if ($cmd -eq 'get_friends_status') 
			{ 'http://data-r03ww.rjgplay.com/'+$cmd; } 
	else 	{ 'http://game-r03ww.rjgplay.com/command/'+$cmd };
	
	$t=doPost $uri $data;
	@{ rxml=if ($t) { [xml]$t}; text=$t; error=$t -match '<internal_error>'; }
}

function dopost_command($data) {	doPostCMD ($data -f (get_context).session.executehdr) }

function f_logon($ctx){
	$xmlfilename=getSavedXmlDataFileName;
	$ctx.session=@{  autdata= 'uid="{0}" auth_key="{1}"' -f $ctx.ids.uid , $ctx.ids.auth_key; };
	$r= doPostCMD ('<get_friends_info {0}/>' -f  $ctx.session.autdata); 
	$rec=  @{ time=$r.rxml.response.friends_info.time ; sign=$r.rxml.response.friends_info.sign; }
	$ctx.session.friends_info = ' <friends_info time="{0}" sign="{1}"><friends/></friends_info>' -f $rec.time, $rec.sign; 

	$r= doPostCMD  ('<get_friends_status {0}>{1}</get_friends_status>' -f $ctx.session.autdata, $ctx.session.friends_info);  
	$rec=  @{ time=$r.rxml.friends_status.time; sign=$r.rxml.friends_status.sign ;};
	$ctx.session.friends_status ='<friends_status sign="{1}" time="{0}"/>' -f $rec.time, $rec.sign; 

	$r= doPostCMD ('<get_game_info {0}><data>{1}</data></get_game_info>' -f $ctx.session.autdata, $ctx.session.friends_status); 
	if (!$config.DebugInternal) {
		$ctx.session.gameinfo=@{ text=$r.text; rxml=$r.rxml; xuser=$r.rxml.response.init_game.user; userid=$ctx.ids.uid;}
		$ctx.session.usersid = $r.response.init_game.user.sid;
		$ctx.session.executehdr='{0} sid="{1}"' -f $ctx.session.autdata,$ctx.session.usersid ;
		$ctx.session.gameinfo.text | out-file $xmlfilename;
	}else {
		write-host '---TEST MODE---'
		$ctx.session.gameinfo= loadprevios_gc 'onlyload';
	}
	parse_userdata $ctx.session.gameinfo | out-null;
}
function loadprevios_gc( $onlyload ) { $ctx=get_context; 
	$xmlf= getSavedXmlDataFileName;
	$txt= get-content $xmlfilename; $x= [xml]$txt;
	$gc=@{ text=$txt; rxml=$x; xuser=$x.response.init_game.user; userid=$ctx.ids.uid;	}
	if ($onlyload) { return $gc; }
	parse_userdata $gc;
}

function parse_user_power_stat( $gc ){
	#soldier grenade,rpg,healkit,armor
	$meta=@{ 	
		soldier=@{ 	art= 'grenade','rpg','healkit','armor';  }; 
		gunner=@{	art='single_target','mass_attack','healkit','armor';}; 
		base_tank=@{art='heavy_shot','spree_shot','healkit','armor'; };
	};	
	function getvar($nm)  { $gc.vars[$nm] };
	function getvars() { 
        $args | %{ getvar $_ }; }
	function getupgradelevel( $nm , $art) { 	for ($i=7;$i -ge 1;$i--) { $nr=getvar ('card_{0}_{1}_upgrade_{2}_level_item' -f $nm,$art,$i); if ($nr) { return $i }; }; return 0 };
	function getlevel( $r , $rnm , $nm , $art ) { $l=$r[$nm]=getvar ('card_{0}_{1}_level_item' -f $nm,$art);  $r.$rnm+='{0,2}.{1}' -f [int]$l,(getupgradelevel $nm $art); }
	function getunitd( $nm ) {  $r=@{ bs=@(); arts=@(); };
			'health','infantry_damage','armor_damage' | %{  getlevel $r 'bs' $nm $_ } ;
			$meta[$nm].art | %{  getlevel $r 'arts' $nm $_ } ; 
			$r.text = '{0}|{1}' -f ($r.bs -join ' '),($r.arts -join ' ');  
			return $r;
	};		
	$pd = @{ uid=$uid;wins=getvar 'rate_win_item';lose=getvar 'rate_lose_item'; };
  
	$pd.pow_s='CФ={0,2} {1,2};' -f (getvars 'strength_item' 'final_strange_item');
	$pd.units_s= ( 'soldier','gunner','base_tank' | %{ ' {0}[{1}]' -f $_[0],(getunitd $_).text  } ) -join ''
	$pd.wins_s= 'wins={0,2}% {1,4};' -f (idiv ($pd.wins*100) ($pd.wins+$pd.lose)), ($pd.wins+$pd.lose);
	$pd.fulltext= '{0,23} {1} {2} {3}' -f $gc.userid,$pd.pow_s,$pd.wins_s,$pd.units_s;
	return $pd;
}


function parse_userdata($gc , $xuser ) { #response.user_info.user
	if (!$gc) { return; }
	if ($xuser) { $gc.xuser=$xuser };
	$gc.vars=@{};
	$gc.xuser.items.ChildNodes | where{$_}|%{ $gc.vars[$_.type] = [int]$_.count; } | out-null;
	$gc.battle_notify=@{};
	$gc.xuser.notifications.ChildNodes | where{$_}|%{ 	$gc.battle_notify[$_.date] = @{ id=$_.date; date= $_.date; innertext= $_.innertext; };	}; 
	$gc.stat=parse_user_power_stat $gc
	return $gc;
}

function get_user_info( $task ){ # user dirtofile=''
	if ($task.contains('dirtofile')) { if (!$task.dirtofile) {$task.dirtofile=$config.dirs.aliendata;}; 
		$destfile='{0}\{1}' -f $task.dirtofile,($task.user -replace ':','-');
	};
	if ($config.DebugInternal) {
		$txt = get-content $destfile; [xml]$x=$txt;
		$res=@{	rxml=if ($txt) { $x }; text=$txt };
	} else {
		$res=dopost_command "<get_user_info {0}><user>$($task.user)</user></get_user_info>" ;
		if ($destfile) { 	$res.destfile=$destfile; $res.text | out-file $destfile;  };
	}	
	$res.destfile=$destfile;
	$res.userid= $task.user;
	$res.xuser= $res.rxml.response.user_info.user;
	$res= parse_userdata $res 
  return $res;
}

function printusage(){
	write-host " Создайте файл в котором хранится ваш ID и authkey!
	Файл должен иметь имя 'usbot-<любое имя>.ps1'.
	@{ ids=@{
		uid='Ваш ID например od:4455667'; 
		auth_key='Ваш key 11191911160e7b52ab1cbab0111b5222';
	}};
	Как узнать ID и  auth_key - смотрите http://gamecrisis.ru/power.html.	
	Можно ввести эти поля в начало данного файла в $config=@{ current=@{ 	ids=@{ uid='*'; auth_key='*'; };	};
	";
};

function rw_cashsign( $d ) {
 $fn = (. $config.files.last_battles_cache);
 if ($d) { $d | out-file $fn }
 elseif ([io.file]::exists($fn)) 
	{ 	get-content $fn |%{$_.trim()}|where{$_ -match '\d+'}| select -first 1; }
}
function main(){
	$ctx = $config.current;
	if (!$ctx.ids.uid) {
		foreach ( $d in "$BaseDirectory\logons",$ScriptDir)	{ $fullfn =(get-childitem "$d\usbot-*.ps1" | select -first 1).FullName; if ($fullfn) { break; } }
		if (!$fullfn) { printusage; return; }
		$ctx = $config.current = . $fullfn;
	};	
	
	f_logon $ctx | out-null;
	$gc=$ctx.session.gameinfo;
	
	$lastkey=rw_cashsign;
    #$lastkey='';
	$newbattles=$gc.battle_notify.values |where { $_.date -gt $lastkey }
	if (!$newbattles) { return; }
	$newbattles | %{ $r=$_; $r.innertext -replace '#:','=' -replace '\{|\}|\#|\[|\]','' -split ','| %{ $a=$_ -split '='; $r[$a[0].trim()]=$a[1].trim(); };  }
	$newbattles= $newbattles  | where { $_.notification_type -eq 'pvp_result' } | sort {$_.date}; 
	rw_cashsign ($newbattles|select -last 1).date;
	#<notification id="954" date="1448788334">{#notification_type#:#clan_tournament_battle_result#, #arena_type#:#pvp_clan_1vs1_2_arena#, #win#:#0#, #clan_id#:#1276f564928149ad79bd7a6c960ff126#}</notification>
	
	$textarr=$newbattles| %{ $r=$_;	
		$agc=get_user_info @{ user=$r.enemies; dirtofile='' };
		if ($agc) {
		'{0} >{1,5}.{2,5} :: {3} || {4}' -f (get_dt $r.date).tostring('dd.MM.yyyy hh:mm:ss'),'pvp',('WIN','LOSS')[[int]$r.win], $gc.stat.fulltext  , $agc.stat.fulltext
		} else { 
		 write-host " не удалось загрузить данные $($r.enemies)" -f blue	
		}
	
	};
	$textarr | out-file (. $config.files.ubattlelog) -Encoding 'utf8' -append; 
	
};

prepConfig;
main;

