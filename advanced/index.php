<?php
/* Detailed Pi-Hole Block Page: Show "Website Blocked" if user browses to site, but not to image/file requests based on the work of WaLLy3K for DietPi & Pi-Hole */

$uri = escapeshellcmd($_SERVER['REQUEST_URI']);
$serverName = escapeshellcmd($_SERVER['SERVER_NAME']);

// Retrieve server URI extension (EG: jpg, exe, php)
$uriExt = pathinfo($uri, PATHINFO_EXTENSION);

// Define which URL extensions get rendered as "Website Blocked"
$webExt = array('asp', 'htm', 'html', 'php', 'rss', 'xml');

if(in_array($uriExt, $webExt) || empty($uriExt))
{
	// Requested resource has an extension listed in $webExt
	// or no extension (index access to some folder incl. the root dir)
	$showPage = true;
}
else
{
	// Something else
	$showPage = false;
}

// Handle incoming URI types
if (!$showPage)
{
?>
<html>
<head>
<script>window.close();</script></head>
<body>
<img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7">
</body>
</html>
<?php
	die();
}

// Get Pi-Hole version
$piHoleVersion = exec('cd /etc/.pihole/ && git describe --tags --abbrev=0');

// Don't show the URI if it is the root directory
if($uri == "/")
{
	$uri = "";
}

?>
<!DOCTYPE html>
<head>
	<meta charset='UTF-8'/>
	<title>Website Blocked</title>
	<link rel='stylesheet' href='http://<?php echo $_SERVER['SERVER_ADDR']; ?>/admin/blockingpage.css'/>
	<link rel='shortcut icon' href='http://<?php echo $_SERVER['SERVER_ADDR']; ?>/admin/img/favicon.png' type='image/png'/>
	<meta name='viewport' content='width=device-width,initial-scale=1.0,maximum-scale=1.0, user-scalable=no'/>
	<meta name='robots' content='noindex,nofollow'/>
</head>
<body>
<header>
	<h1><a href='/'>Website Blocked</a></h1>
</header>
<main>
	<div>Access to the following site has been blocked:<br/>
	<span class='pre msg'><?php echo $serverName.$uri; ?></span></div>
	<div>If you have an ongoing use for this website, please ask the owner of the Pi-Hole in your network to have it whitelisted.</div>
	<input id="domain" type="hidden" value="<?php echo $serverName; ?>">
	<input id="quiet" type="hidden" value="yes">
	<button id="btnSearch" class="buttons blocked" type="button" style="visibility: hidden;"></button>
	This page is blocked because it is explicitly contained within the following block list(s):
	<pre id="output" style="width: 100%; height: 100%;" hidden="true"></pre><br/>
	<div class='buttons blocked'><a class='safe' href='javascript:history.back()'>Go back</a>
</main>
<footer>Generated <?php echo date('D g:i A, M d'); ?> by Pi-hole <?php echo $piHoleVersion; ?></footer>
<script src="http://<?php echo $_SERVER['SERVER_ADDR']; ?>/admin/js/other/jquery.min.js"></script>
<script src="http://<?php echo $_SERVER['SERVER_ADDR']; ?>/admin/js/pihole/queryads.js"></script>
<script>
	$( "#btnSearch" ).click();
</script>
</body>
</html>
