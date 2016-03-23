#param(  [alias("userfiles","u")] $in_cfg_userfiles )
$g__DebugInternal=$null;
#$g__DebugInternal=1
$opt_loadfromlocal = if ($g__DebugInternal) {'only'} else { 'notnew' };
$opt_maxusers = (100*1000) ;

$BaseDirectory = [IO.Path]::GetFullPath($($MyInvocation.MyCommand.Definition | split-path -parent)+'\..');
$null = . "$BaseDirectory\cfg\bot_gen_lib.ps1" 'shortmode';

$work=@{
	unhandledlist=@{};
	handledlist=@{};
	errors=0;
	newusers=0;
};

function dowork(){
	function thetick ($id) {
		$t= [datetime]::now - $work.timestart;
		$speed= $work.handledlist.count / $t.totalseconds;
		$data = $t.tostring(),$work.unhandledlist.count,$work.handledlist.count,$speed,$work.newusers,$work.errors,$id;
		$host.UI.RawUI.WindowTitle='Прошло {0}   В очереди {1} Обработано {2} ({3:F3} 1/c) Новых {4} Ошибок {5} Текущий {6} ' -f $data ;
	};
	function getlist_enemies($res) {
		$text= if ($res.text -isnot [array]) { $res.response.user_info.user.notifications.ChildNodes | %{$_.innertext} } else { $res.text}
		$text | where { $_ -match '\#enemies\#\:\[\#(?<uid>\w+\:\d+)\#\]'; }| %{ $matches.uid }
	};
	function getuserdata($id) { 
		$fn = '{0}\{1}' -f $config.dirs.aliendata,($id -replace '\:','-');
		if (([io.file]::exists($fn)) -and ($opt_loadfromlocal)) {
			$t=get-content $fn;
			@{ text=$t; }
		} elseif ($opt_loadfromlocal -ne 'only') { 
			$work.newusers++;
			try{	get_user_info @{user=$id; dirtofile=''} $false; } catch { write-host $_ -f red;  return @{error=$_;}}
		} else{
			@{ error='load only local' }
		};
	};
	function handle($id) {
		thetick $id ;
		$res=getuserdata $id;
		$work.handledlist[$id]=1; $work.unhandledlist.remove($id);
		if ($res.error) { $work.errors++; write-host "error at '$id'" -f yellow; return; }
		if (($work.handledlist.count + $work.unhandledlist.count) -ge $opt_maxusers) { return; }
		$l = getlist_enemies $res;
		$l |where{$_}|where {!$work.handledlist.contains($_) -and !$work.unhandledlist.contains($_)} | %{ $work.unhandledlist[$_]=1; }
	}
	$work.timestart= [datetime]::now;
	while (1) {
		$i=0;$a=foreach ($nm in $work.unhandledlist.keys) { if (!$work.handledlist.contains($nm)){ $i++; if ($i -gt 100) {break;}  $nm;}}
		#$a=$work.unhandledlist.keys|where {!$work.handledlist.contains($_)} |select -first 100;
		if (!$a) { break }
		foreach ($nm in $a) { handle $nm | out-null	};
	};	
}
function Main(){
	$config.log.i_allowed=@{};
	$ufn= (get-childitem "$BaseDirectory\logons\special\closure-*.ps1" | select -first 1).FullName
	$ctx = load_personage $ufn
	write-host ('logged by {0} {1}' -f $ctx.username,$ctx.ids.uid)
	do_base_connection $ctx 'short';
	write-host 'scan start dir...'
	get-childitem $config.dirs.aliendata | %{($_.name -split '\.')[0] -replace '\-',':'} | %{ $work.unhandledlist[$_]=0; };
	write-host 'start closure...'
	dowork;
	#$res.textres | out-host
}

PrepareConfig;
Main;
close_context_files;
