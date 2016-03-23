param( $in_user_fullname='vk:48450570' )
$g__DebugInternal=$null;
#$g__DebugInternal=1;

$BaseDirectory = [IO.Path]::GetFullPath($($MyInvocation.MyCommand.Definition | split-path -parent)+'\..');
$null = . "$BaseDirectory\cfg\bot_gen_lib.ps1" 'shortmode';






function Main(){
	$lfn = . $config.log.logbattlesfn;
	$dt1= get-content $lfn;
	$dt1=$dt1 -replace ':: \w+:\d+',':: *id*'; 
	$nms = $dt1 | %{ $r=$_ -match '[.\w]+\>';$matches[0]} | group | %{ $_.group[0] -replace '\>','' };
	$nms | out-host;
	$i=0; $nms | %{ $dt1=$dt1 -replace " +$_>"," user$i>"; $i++; }
	$dt1 | select -first 10 | out-host
	$dt1 | out-file "$lfn.anonim.txt"
}
Main| out-null;
close_context_files;
