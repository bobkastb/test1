#param(  [alias("userfiles","u")] $in_cfg_userfiles )
$g__DebugInternal=$null;
#$g__DebugInternal=1

$BaseDirectory = [IO.Path]::GetFullPath($($MyInvocation.MyCommand.Definition | split-path -parent)+'\..');
$null = . "$BaseDirectory\cfg\bot_gen_lib.ps1" 'shortmode';
set_grouplog_allowed 'debug' 0 0
$config.log.filenm="$($config.dirs.logs)\log.distribution-user.txt";

function distrib_memory( $write ){
	rw_memoryfile $config 'memory' ( . $config.log.globalmemfile ) $write
}	

function post_command_nohand( $cmd ){
	$cmdinf=@{ cmd=$cmd; disablehander=$true; disablecomment=$true; };
	dopost_ofproduce $config.current $cmdinf $args[0] $args[1] $args[2] $args[3] $args[4] $args[5] $args[6]
};

function distrib_schemes() {
	$mexch=$config.metaupgrade.exchange_shemes;
	$resdata=@{};
	
	function getlistfiles( $flist ) { browsUsersConfFiles $flist | group {$_.name} | %{ $_.group[0] } };
	function getlogonuid($uid) { if ($uid -is [hashtable]) { $uid.ids.uid} else { $uid} }
	function getlogontype($uid) { ((getlogonuid $uid) -split ':')[0]   }
	function dologon($ctx){ if (!$ctx.logged) { do_base_connection $ctx 'short'; $ctx.logged=$true; } };
	function sendschemes($ctx , $to ) { $lid= getlogonuid $ctx;
		$resdata[$to]='{0}{1}, ' -f $resdata[$to],($lid);
		#write-host "sending to $to"	
		post_command_nohand 'send_scheme' $to 
		post_command_nohand 'send_eventscheme' $to 
	};
	function sizearray($a) { if ($a -is [array]) { $a.count } elseif ($a) {1} else {0}}
	function maked_name( $ctxrec ) { '{0}_{1}' -f ($ctxrec.uid -split ':')[0] , ($ctxrec.mail -split '@')[0]; }
	
	distrib_memory | out-null;
	$memdto =getOrNew_field $config.memory.today 'distribto' { @{complete=0} }
	#if ($memdto.complete) { return; }
	$memdto.complete=1;
	$tolist=(get-content "$BaseDirectory\logons\distribution\receiver-list.txt") -match '\w\w\:\d+' | %{$_.trim()};
	$fromlist= . "$BaseDirectory\logons\distribution\ssclist-1.ps1";
	2
	"to-----{0}" -f ($tolist -join ' ') | out-host;
	$gchanges=0;
	foreach ($ctxrec in $fromlist) {
		$ctx = @{ username=maked_name $ctxrec; ids=$ctxrec; session=@{webclient=$null;	autdata='';	}; } 
		$config.current=$ctx= load_personage $ctx @{ initonly=$true; };
		$ctx.log=@{ filenm=$config.log.filenm };
		$logonuid=getlogonuid $ctx;	$logontype=getlogontype $logonuid
		$list = $tolist -match "^$logontype\:";
		dolog $MLVL_USERBASE ('use src {0} {1} {2} send:{3}' -f $ctx.username,$logonuid,(sizearray $list),($list -join ' '))
		if (!$list) { continue; }
		try{
			dologon $ctx | out-null;
		}catch { write-host $_; dolog $MLVL_ERR "logon error $logonuid" yellow; continue; }
		try{
		foreach ($to in $list) {	sendschemes $ctx $to | out-null	};
		}catch{ write-host $_; dolog $MLVL_ERR "send error $logonuid -> $to" gray; }
	};
	$config.current=$null;
	$memdto.complete=$resdata.count;
	distrib_memory 'write'| out-null;
	return $resdata;
};

function Main(){
	#$config.log.i_allowed=@{};
	#setlogallowed ($MLVL_POST,$MLVL_PRODUCE_FULL) 
	$r= distrib_schemes ;
	dolog $MLVL_USERBASE ($r | out-string)
}

Main;
close_context_files;
