<?php
// What chat.php (Prism) and mp.php (the crystal exhibits) share: replies, settings with their keys, the same-site check and the counters behind the rate limits. Not reachable from the web (api/.htaccess).
//
// Settings come from crystalminer-config.php or a .env file in this folder or one of the four above it (put them above public_html, where the web server cannot hand them out), else from the server's environment. See config.example.php.
declare(strict_types=1);

function reply(int $code, array $body): void {
    http_response_code($code);
    echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

// KEY=VALUE lines, as in the game's .env (tools/luanti_with_env.cmd); # starts a comment.
function read_env_file(string $path): array {
    $out = [];
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) continue;
        [$k, $v] = array_map('trim', explode('=', $line, 2));
        $out[$k] = trim($v, "\"'");
    }
    return $out;
}

// The settings: defaults, then every crystalminer-config.php found, the nearest one winning, plus the .env variables (nearest first) in 'env'.
function settings(array $defaults): array {
    $configs = [];
    $env = [];
    $dir = __DIR__;
    for ($i = 0; $i < 5; $i++) {
        if (is_file($dir . '/crystalminer-config.php')) $configs[] = (array) require $dir . '/crystalminer-config.php';
        if (is_file($dir . '/.env')) $env = array_replace(read_env_file($dir . '/.env'), $env);
        $dir = dirname($dir);
    }
    $config = $defaults;
    foreach (array_reverse($configs) as $c) $config = array_replace($config, $c);
    $config['env'] = $env;
    return $config;
}

function setting(array $config, string $name): string {
    $v = $config['env'][$name] ?? getenv($name);
    return is_string($v) ? trim($v) : '';
}

// Only this site's own pages may use the API from a browser.
function same_site_only(): void {
    $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
    if ($origin !== '' && parse_url($origin, PHP_URL_HOST) !== explode(':', $_SERVER['HTTP_HOST'] ?? '')[0]) reply(403, ['error' => 'Not allowed from another site.']);
}

// Counters and caches live in cache/. .htaccess denies them to the web; they are also .php files that begin by exiting, so a server that ignores .htaccess shows nothing of them either. Visitors are stored as a hash of their address, never the address.
const GUARD = "<?php exit; ?>\n";

function cache_dir(): ?string {
    $dir = __DIR__ . '/cache';
    if (!is_dir($dir) && !@mkdir($dir, 0700, true)) return null;
    return $dir;
}

function visitor(): string {
    return hash('sha256', ($_SERVER['REMOTE_ADDR'] ?? 'unknown') . '|crystalminer');
}

// Reads and updates one counter file under a lock. $update(state or null) returns [new state, refusal message or null]; the state is saved only when nothing was refused.
function counter(string $file, callable $update): ?string {
    $fh = @fopen($file, 'c+');
    if (!$fh || !flock($fh, LOCK_EX)) return null;
    $raw = (string) stream_get_contents($fh);
    $state = json_decode(substr($raw, strlen(GUARD)), true);
    [$state, $refusal] = $update(is_array($state) ? $state : null);
    if ($refusal === null) { ftruncate($fh, 0); rewind($fh); fwrite($fh, GUARD . json_encode($state)); }
    flock($fh, LOCK_UN);
    fclose($fh);
    return $refusal;
}

// At most $max uses in an hour by one visitor, in the counter named $name; a refusal message, or null.
function per_visitor_hour(string $name, int $max, string $message): ?string {
    $dir = cache_dir();
    if ($dir === null) return null;
    $now = time();
    return counter($dir . '/' . $name . '_' . visitor() . '.php', function (?array $s) use ($now, $max, $message) {
        $s = $s ?: ['hour' => $now, 'n' => 0];
        if ($now - $s['hour'] >= 3600) { $s['hour'] = $now; $s['n'] = 0; }
        if ($s['n'] >= $max) return [$s, $message];
        $s['n']++;
        return [$s, null];
    });
}

// At most $max uses a day for the whole site, in the counter named $name.
function per_day(string $name, int $max, string $message): ?string {
    $dir = cache_dir();
    if ($dir === null) return null;
    return counter($dir . '/' . $name . '_' . gmdate('Y-m-d') . '.php', function (?array $s) use ($max, $message) {
        $n = (int) ($s['n'] ?? 0);
        if ($n >= $max) return [['n' => $n], $message];
        return [['n' => $n + 1], null];
    });
}
