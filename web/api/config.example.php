<?php
// Settings for Prism's chat (chat.php) and the live crystal exhibits (mp.php). Copy this file to crystalminer-config.php ABOVE your public_html folder (on Hostinger: your home folder, next to public_html), so the web server can never hand it out, and fill in the keys. Both scripts look for it in its own folder and the four above. A .env file in the same places works too (DEEPSEEK_API_KEY=..., CRYSTALMINER_TUTOR_MODEL=..., MP_API=...).
return [
    // The model, as in LiteLLM: deepseek/deepseek-flash, anthropic/claude-opus-5-5, openai/<model>, gemini/<model>, groq/<model>, openrouter/<org>/<model>, litellm_proxy/<model>, ... (README: "The AI tutor").
    'model' => 'deepseek/deepseek-flash',
    // The key for that model's provider. Empty: the provider's variable from a .env file or the server's environment (DEEPSEEK_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY, ...).
    'api_key' => '',
    // Only for a server at an unusual address (a LiteLLM proxy, vLLM, Ollama elsewhere), up to and including /v1.
    'base_url' => '',
    // Limits: seconds between one visitor's questions, questions per visitor per hour, and questions per day for the whole site (a ceiling on the day's API cost).
    'seconds_between' => 4,
    'per_hour' => 60,
    'per_day' => 2000,

    // The crystal-exhibit rooms load a random real structure from the Materials Project (MPContribs) when there is a key, else they show the three built into the game. The key is free with a Materials Project account (https://next-gen.materialsproject.org/api). Empty: MP_API from a .env file or the server's environment.
    'mp_api_key' => '',
    // false keeps the built-in structures even with a key.
    'live_exhibits' => true,
    // Limits: requests per visitor per hour (one room load takes a few), and requests to the Materials Project per day for the whole site. Answers are cached (lists a day, structures 30 days), so repeated loads cost nothing.
    'mp_per_hour' => 240,
    'mp_per_day' => 3000,
];
