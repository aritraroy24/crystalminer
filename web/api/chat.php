<?php
// Prism's chat for the web version. The browser sends a question, the conversation so far, the player's tier and place; this script adds Prism's grounding text (prompt.txt, made by tools/export_web.lua from the game's tutor.lua) and the API key, asks the model, and returns its answer. The key and the grounding text never reach the browser.
//
// The model is named as in LiteLLM, "provider/model", with the same providers and key variables as the game (tutor.lua). Settings come from crystalminer-config.php or a .env file in this folder or one of the four above it (put them above public_html, where the web server cannot hand them out), else from the server's environment. See config.example.php.
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

function reply(int $code, array $body): void {
    http_response_code($code);
    echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

// ------------------------------------------------------------------ settings

const PROVIDERS = [
    'deepseek' => ['name' => 'DeepSeek', 'base' => 'https://api.deepseek.com', 'env' => 'DEEPSEEK_API_KEY', 'model' => 'deepseek-flash'],
    'anthropic' => ['name' => 'Claude', 'anthropic' => true, 'env' => 'ANTHROPIC_API_KEY', 'model' => 'claude-opus-5-5'],
    'openai' => ['name' => 'OpenAI', 'base' => 'https://api.openai.com/v1', 'env' => 'OPENAI_API_KEY'],
    'gemini' => ['name' => 'Google Gemini', 'base' => 'https://generativelanguage.googleapis.com/v1beta/openai', 'env' => 'GEMINI_API_KEY'],
    'groq' => ['name' => 'Groq', 'base' => 'https://api.groq.com/openai/v1', 'env' => 'GROQ_API_KEY'],
    'mistral' => ['name' => 'Mistral', 'base' => 'https://api.mistral.ai/v1', 'env' => 'MISTRAL_API_KEY'],
    'openrouter' => ['name' => 'OpenRouter', 'base' => 'https://openrouter.ai/api/v1', 'env' => 'OPENROUTER_API_KEY'],
    'together_ai' => ['name' => 'Together AI', 'base' => 'https://api.together.xyz/v1', 'env' => 'TOGETHERAI_API_KEY'],
    'xai' => ['name' => 'xAI', 'base' => 'https://api.x.ai/v1', 'env' => 'XAI_API_KEY'],
    'fireworks_ai' => ['name' => 'Fireworks AI', 'base' => 'https://api.fireworks.ai/inference/v1', 'env' => 'FIREWORKS_AI_API_KEY'],
    'perplexity' => ['name' => 'Perplexity', 'base' => 'https://api.perplexity.ai', 'env' => 'PERPLEXITYAI_API_KEY'],
    'cerebras' => ['name' => 'Cerebras', 'base' => 'https://api.cerebras.ai/v1', 'env' => 'CEREBRAS_API_KEY'],
    'ollama' => ['name' => 'Ollama', 'base' => 'http://localhost:11434/v1', 'env_base' => 'OLLAMA_API_BASE', 'keyless' => true],
    'ollama_chat' => ['name' => 'Ollama', 'base' => 'http://localhost:11434/v1', 'env_base' => 'OLLAMA_API_BASE', 'keyless' => true],
    'lm_studio' => ['name' => 'LM Studio', 'base' => 'http://localhost:1234/v1', 'env' => 'LM_STUDIO_API_KEY', 'env_base' => 'LM_STUDIO_API_BASE', 'keyless' => true],
    'hosted_vllm' => ['name' => 'vLLM', 'base' => '', 'env' => 'HOSTED_VLLM_API_KEY', 'env_base' => 'HOSTED_VLLM_API_BASE', 'keyless' => true],
    'litellm_proxy' => ['name' => 'a LiteLLM proxy', 'base' => 'http://localhost:4000/v1', 'env' => 'LITELLM_PROXY_API_KEY', 'env_base' => 'LITELLM_PROXY_API_BASE', 'keyless' => true],
];

const DEFAULTS = [
    'model' => '',                // "provider/model"; empty: CRYSTALMINER_TUTOR_MODEL, else deepseek/deepseek-flash
    'api_key' => '',              // empty: the provider's variable (DEEPSEEK_API_KEY, ...)
    'base_url' => '',             // empty: the provider's usual address
    'max_tokens' => 1500,
    'timeout' => 60,
    'seconds_between' => 4,       // per visitor
    'per_hour' => 60,             // per visitor
    'per_day' => 2000,            // for the whole site: a ceiling on what the API can cost in a day
];

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

function settings(): array {
    $config = DEFAULTS;
    $env = [];
    $dir = __DIR__;
    for ($i = 0; $i < 5; $i++) {
        if (is_file($dir . '/crystalminer-config.php')) { $config = array_replace($config, (array) require $dir . '/crystalminer-config.php'); }
        if (is_file($dir . '/.env')) { $env = array_replace(read_env_file($dir . '/.env'), $env); }
        $dir = dirname($dir);
    }
    $config['env'] = $env;
    return $config;
}

function setting(array $config, string $name): string {
    $v = $config['env'][$name] ?? getenv($name);
    return is_string($v) ? trim($v) : '';
}

// The model, its provider and how to reach it, as tutor.lua's T.config does.
function resolve(array $config): array {
    $spec = trim((string) $config['model']);
    if ($spec === '') $spec = setting($config, 'CRYSTALMINER_TUTOR_MODEL');
    if ($spec === '') $spec = 'deepseek/deepseek-flash';
    if (!preg_match('~^([A-Za-z0-9_]+)/(.+)$~', $spec, $m) || !isset(PROVIDERS[strtolower($m[1])])) {
        return ['error' => "the model must be provider/model, as in deepseek/deepseek-flash"];
    }
    $prefix = strtolower($m[1]);
    $p = PROVIDERS[$prefix];
    $model = trim($m[2]);
    $key = trim((string) $config['api_key']);
    if ($key === '' && isset($p['env'])) $key = setting($config, $p['env']);
    if ($key === '') $key = setting($config, 'CRYSTALMINER_TUTOR_API_KEY');
    if (!empty($p['anthropic'])) {
        if ($key === '') $key = setting($config, 'ANTHROPIC_API_KEY');
        return $key === '' ? ['error' => 'no API key for Claude'] : ['anthropic' => true, 'url' => 'https://api.anthropic.com/v1/messages', 'model' => $model, 'key' => $key, 'name' => $p['name']];
    }
    $base = trim((string) $config['base_url']);
    if ($base === '' && isset($p['env_base'])) {
        $base = setting($config, $p['env_base']);
        if ($base !== '' && !preg_match('~/v1/?$~', $base)) $base = rtrim($base, '/') . '/v1';
    }
    if ($base === '') $base = $p['base'];
    $base = rtrim($base, '/');
    if (!preg_match('~^https?://\S+$~', $base)) return ['error' => 'no address for ' . $p['name']];
    if ($key === '' && empty($p['keyless'])) return ['error' => 'no API key for ' . $p['name'] . ' (' . $p['env'] . ')'];
    return ['anthropic' => false, 'url' => $base . '/chat/completions', 'model' => $model, 'key' => $key, 'name' => $p['name']];
}

// ------------------------------------------------------------------ limits

// A few questions per visitor, and a ceiling for the whole site per day, kept in files in cache/. .htaccess denies them to the web; they are also .php files that begin by exiting, so a server that ignores .htaccess shows nothing of them either. Visitors are stored as a hash of their address, never the address.
const GUARD = "<?php exit; ?>\n";

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

function within_limits(array $config): ?string {
    $dir = __DIR__ . '/cache';
    if (!is_dir($dir) && !@mkdir($dir, 0700, true)) return null;
    $now = time();
    $visitor = hash('sha256', ($_SERVER['REMOTE_ADDR'] ?? 'unknown') . '|crystalminer');
    $refusal = counter($dir . '/v_' . $visitor . '.php', function (?array $s) use ($now, $config) {
        $s = $s ?: ['last' => 0, 'hour' => $now, 'n' => 0];
        if ($now - $s['hour'] >= 3600) { $s['hour'] = $now; $s['n'] = 0; }
        if ($now - $s['last'] < $config['seconds_between']) return [$s, 'Give Prism a moment: you can ask again in a few seconds.'];
        if ($s['n'] >= $config['per_hour']) return [$s, 'That is a lot of questions for one hour. Try again later, or ask your teacher.'];
        $s['last'] = $now;
        $s['n']++;
        return [$s, null];
    });
    if ($refusal !== null) return $refusal;
    return counter($dir . '/day_' . gmdate('Y-m-d') . '.php', function (?array $s) use ($config) {
        $n = (int) ($s['n'] ?? 0);
        if ($n >= $config['per_day']) return [['n' => $n], 'Prism has answered all the questions it can for today. Try again tomorrow.'];
        return [['n' => $n + 1], null];
    });
}

// ------------------------------------------------------------------ the request

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') reply(405, ['error' => 'Use POST.']);
// Only this site's own pages may use the chat from a browser.
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if ($origin !== '' && parse_url($origin, PHP_URL_HOST) !== explode(':', $_SERVER['HTTP_HOST'] ?? '')[0]) reply(403, ['error' => 'Not allowed from another site.']);

$raw = file_get_contents('php://input', false, null, 0, 65536);
$in = json_decode((string) $raw, true);
if (!is_array($in)) reply(400, ['error' => 'The question could not be read.']);

$clean = fn($s, int $max) => mb_substr(preg_replace('/[\x00-\x08\x0B-\x1F\x7F]/u', '', trim((string) $s)) ?? '', 0, $max);
$question = $clean($in['question'] ?? '', 1000);
if ($question === '') reply(400, ['error' => 'Ask a question first.']);
if (mb_strlen($question) > 300) reply(400, ['error' => 'That is too long for the tutor. Please keep it under 300 characters.']);
$tier = max(0, min(5, (int) ($in['tier'] ?? 0)));
$place = $clean($in['place'] ?? '', 100) ?: 'the museum';

// Earlier turns: only questions with their answers, alternating, the last twelve messages (tutor.lua's chat_request).
$turns = [];
$h = is_array($in['history'] ?? null) ? array_values($in['history']) : [];
for ($i = 0; $i + 1 < count($h); $i++) {
    $q = $h[$i]; $a = $h[$i + 1];
    if (is_array($q) && is_array($a) && ($q['role'] ?? '') === 'user' && ($a['role'] ?? '') === 'assistant') {
        $turns[] = ['role' => 'user', 'content' => $clean($q['text'] ?? '', 1000)];
        $turns[] = ['role' => 'assistant', 'content' => $clean($a['text'] ?? '', 4000)];
        $i++;
    }
}
$turns = array_slice($turns, -12);
$turns[] = ['role' => 'user', 'content' => "Student tier: $tier\nStudent is in: $place\nQuestion: $question"];

$config = settings();
$target = resolve($config);
if (isset($target['error'])) {
    error_log('crystalminer chat: ' . $target['error']);
    reply(503, ['error' => 'Prism is not set up on this site yet (' . $target['error'] . ').']);
}
$limited = within_limits($config);
if ($limited !== null) reply(429, ['error' => $limited]);

$prompt = (string) @file_get_contents(__DIR__ . '/prompt.txt');
if ($prompt === '') reply(503, ['error' => 'Prism is not set up on this site yet (prompt.txt is missing).']);
// The grounding text is the game's; the web version has keys where the game has commands.
$prompt .= "
THIS IS THE WEB VERSION, in a browser. There is no chat command line: the game's commands /step, /byhand, /tour, /hunt, /elements, /stereogram, /showcase and /challenge do not exist here, so never suggest them. The keys are: G the guide to this place, Q the quiz, I the progress board (with Go there buttons), P this chat, H back to the Portal Hall, M the symmetry markers, K fly, J fast; in the Free Lab, L chooses its symmetry and X works out the symmetry of a build (the game's /symmetry and /whatsymmetry). Point to these keys instead.
";

if ($target['anthropic']) {
    $body = ['model' => $target['model'], 'max_tokens' => 4096, 'system' => $prompt, 'messages' => $turns];
    $headers = ['Content-Type: application/json', 'x-api-key: ' . $target['key'], 'anthropic-version: 2023-06-01'];
} else {
    $body = ['model' => $target['model'], 'messages' => array_merge([['role' => 'system', 'content' => $prompt]], $turns),
        'max_tokens' => (int) $config['max_tokens'], 'temperature' => 0.2];
    $headers = ['Content-Type: application/json'];
    if ($target['key'] !== '') $headers[] = 'Authorization: Bearer ' . $target['key'];
}

$ch = curl_init($target['url']);
curl_setopt_array($ch, [
    CURLOPT_POST => true, CURLOPT_POSTFIELDS => json_encode($body, JSON_UNESCAPED_UNICODE), CURLOPT_HTTPHEADER => $headers,
    CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => (int) $config['timeout'], CURLOPT_CONNECTTIMEOUT => 10,
]);
$res = curl_exec($ch);
$code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
$err = curl_errno($ch);
curl_close($ch);

if ($res === false) reply(502, ['error' => $err === CURLE_OPERATION_TIMEDOUT ? 'Prism took too long to answer. Try a simpler question.' : 'Prism could not be reached.']);
if ($code >= 400) {
    error_log("crystalminer chat: {$target['name']} answered HTTP $code");
    $msg = $code === 429 ? 'Prism is busy right now. Try again in a minute.'
        : ($code === 401 || $code === 403 ? 'Prism is unavailable: the AI service refused the API key.'
        : ($code === 404 ? 'Prism is unavailable: the AI service does not know that model.' : "Prism is unavailable (error $code)."));
    reply(502, ['error' => $msg]);
}
$out = json_decode($res, true);
if (!is_array($out)) reply(502, ['error' => 'Prism sent an unreadable reply.']);

if ($target['anthropic']) {
    if (($out['stop_reason'] ?? '') === 'max_tokens') reply(502, ['error' => "Prism's answer was cut off. Try a shorter or simpler question."]);
    $text = implode('', array_map(fn($b) => ($b['type'] ?? '') === 'text' ? (string) $b['text'] : '', $out['content'] ?? []));
} else {
    $choice = $out['choices'][0] ?? [];
    if (($choice['finish_reason'] ?? '') === 'length') reply(502, ['error' => "Prism's answer was cut off. Try a shorter or simpler question."]);
    $text = (string) ($choice['message']['content'] ?? '');
    // Some reasoning models put their thinking in the reply; it is never shown.
    $text = preg_replace('~^\s*<think>.*?</think>~s', '', $text) ?? $text;
}
$text = trim(preg_replace('/^\s*(Prism|Tutor)\s*:\s*/i', '', $text) ?? $text);
if ($text === '') reply(502, ['error' => 'Prism had nothing to say. Try rephrasing your question.']);
reply(200, ['answer' => $text, 'service' => $target['name'] . ' (' . $target['model'] . ')']);
