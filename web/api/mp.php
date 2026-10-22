<?php
// The Materials Project lookups behind the web version's live crystal exhibits: the two requests the game itself makes (exhibit_dynamic.lua), with the key added on the server, so it never reaches the browser.
//
//   mp.php?status                   whether live structures are on: { "live": true|false }
//   mp.php?element=Ti               structures whose name contains Ti: /structures/?name__icontains=Ti&_limit=100&_fields=id,name
//   mp.php?id=<24 hex digits>       one structure: /structures/<id>/?_fields=id,name,md5,lattice,sites
//
// The browser does the rest (web/js/exhibit_live.js, a port of exhibit_live.lua): it picks the element, filters, checks and draws. The key is MP_API (or MP_API_KEY, CRYSTALMINER_MP_API_KEY) in the .env file above public_html, or mp_api_key in crystalminer-config.php; 'live_exhibits' => false there (or CRYSTALMINER_LIVE_EXHIBITS=0) turns live structures off, and the rooms show the structures built into the game. Answers are cached, so a busy class asks the Materials Project much less than it asks this script.
declare(strict_types=1);
require __DIR__ . '/common.php';

header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');

const DEFAULTS = [
    'live_exhibits' => true,
    'mp_api_key' => '',
    'mp_api_url' => '',            // empty: CRYSTALMINER_MP_API_URL, else https://contribs-api.materialsproject.org
    'mp_per_hour' => 240,          // requests to this script per visitor per hour
    'mp_per_day' => 3000,          // requests to the Materials Project per day, for the whole site
    'mp_list_seconds' => 86400,    // how long a list of names is kept
    'mp_record_seconds' => 2592000, // how long a structure is kept (30 days)
];

$config = settings(DEFAULTS);
$key = trim((string) $config['mp_api_key']);
foreach (['MP_API', 'MP_API_KEY', 'CRYSTALMINER_MP_API_KEY'] as $name) if ($key === '') $key = setting($config, $name);
$off = strtolower(setting($config, 'CRYSTALMINER_LIVE_EXHIBITS'));
$live = $config['live_exhibits'] !== false && !in_array($off, ['0', 'false', 'off', 'no'], true) && $key !== '';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'GET') reply(405, ['error' => 'Use GET.']);
same_site_only();
if (isset($_GET['status'])) { header('Cache-Control: no-store'); reply(200, ['live' => $live]); }
if (!$live) reply(503, ['error' => 'Live structures are off on this site.']);

$base = trim((string) $config['mp_api_url']);
if ($base === '') $base = setting($config, 'CRYSTALMINER_MP_API_URL');
if ($base === '') $base = 'https://contribs-api.materialsproject.org';
$base = rtrim($base, '/');

// Only the game's two requests, with checked parameters: nothing else can be asked through this script.
$element = (string) ($_GET['element'] ?? '');
$id = (string) ($_GET['id'] ?? '');
if ($element !== '' && preg_match('/^[A-Z][a-z]?$/', $element)) {
    $url = $base . '/structures/?name__icontains=' . $element . '&_limit=100&_fields=id,name';
    $ttl = (int) $config['mp_list_seconds'];
} elseif ($id !== '' && preg_match('/^[0-9a-f]{24}$/', $id)) {
    $url = $base . '/structures/' . $id . '/?_fields=id,name,md5,lattice,sites';
    $ttl = (int) $config['mp_record_seconds'];
} else {
    reply(400, ['error' => 'Ask for ?element=<symbol> or ?id=<structure id>.']);
}

$refused = per_visitor_hour('mpv', (int) $config['mp_per_hour'], 'That is a lot of crystal structures for one hour. The rooms will show the built-in ones.');
if ($refused !== null) reply(429, ['error' => $refused]);

// The cache: a structure record does not change, and a list of names hardly does.
$dir = cache_dir();
$file = $dir !== null ? $dir . '/mp_' . hash('sha256', $url) . '.php' : null;
if ($file && is_file($file) && time() - filemtime($file) < $ttl) {
    $body = substr((string) file_get_contents($file), strlen(GUARD));
    if ($body !== '') { header('Cache-Control: private, max-age=3600'); echo $body; exit; }
}

$refused = per_day('mpday', (int) $config['mp_per_day'], 'The site has asked the Materials Project for all the structures it may today. The rooms will show the built-in ones.');
if ($refused !== null) reply(429, ['error' => $refused]);

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_HTTPHEADER => ['X-API-KEY: ' . $key, 'Accept: application/json'],
    CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 20, CURLOPT_CONNECTTIMEOUT => 8,
]);
$res = curl_exec($ch);
$code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
$err = curl_errno($ch);
curl_close($ch);
if ($res === false) reply(502, ['error' => $err === CURLE_OPERATION_TIMEDOUT ? 'timeout' : 'request failed']);
if ($code >= 400) {
    error_log("crystalminer exhibits: the Materials Project answered HTTP $code");
    reply(502, ['error' => $code === 401 || $code === 403 ? 'the Materials Project refused the key' : 'http error']);
}
if (!is_array(json_decode($res, true))) reply(502, ['error' => 'bad JSON']);
if ($file) @file_put_contents($file, GUARD . $res, LOCK_EX);
header('Cache-Control: private, max-age=3600');
echo $res;
