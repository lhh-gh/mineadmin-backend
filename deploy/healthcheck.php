<?php

declare(strict_types=1);
/**
 * This file is part of MineAdmin.
 *
 * @link     https://www.mineadmin.com
 * @document https://doc.mineadmin.com
 * @contact  root@imoi.cn
 * @license  https://github.com/mineadmin/MineAdmin/blob/master/LICENSE
 */
// Run outside the application container bootstrap so this probe stays bounded.
$env = static function (string $name, string $default = ''): string {
    $value = getenv($name);
    return $value === false ? $default : $value;
};
$stage = 'http';

try {
    $httpPort = (int) $env('HTTP_PORT', '9501');
    if ($httpPort < 1 || $httpPort > 65535) {
        throw new RuntimeException('Invalid HTTP port.');
    }
    $context = stream_context_create([
        'http' => [
            'method' => 'GET',
            'timeout' => 2.0,
            'ignore_errors' => true,
            'follow_location' => 0,
        ],
    ]);
    $body = @file_get_contents(sprintf('http://127.0.0.1:%d/', $httpPort), false, $context);
    $status = $http_response_header[0] ?? '';
    if ($body === false || ! preg_match('/^HTTP\/\S+ 200(?:\s|$)/', $status)) {
        throw new RuntimeException('HTTP probe failed.');
    }

    $checkDependencies = filter_var($env('HEALTHCHECK_DEPENDENCIES', 'true'), \FILTER_VALIDATE_BOOLEAN);
    if (! $checkDependencies) {
        exit(0);
    }

    $stage = 'mysql';
    if ($env('DB_DRIVER', 'mysql') !== 'mysql') {
        throw new RuntimeException('This deployment probe requires MySQL.');
    }
    $charset = $env('DB_CHARSET', 'utf8mb4');
    if (! preg_match('/^[A-Za-z0-9_]+$/', $charset)) {
        throw new RuntimeException('Invalid MySQL charset.');
    }
    $port = (int) $env('DB_PORT', '3306');
    if ($port < 1 || $port > 65535) {
        throw new RuntimeException('Invalid MySQL port.');
    }
    $pdo = new PDO(
        sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=%s',
            $env('DB_HOST', '127.0.0.1'),
            $port,
            $env('DB_DATABASE', 'mineadmin'),
            $charset
        ),
        $env('DB_USERNAME', 'mineadmin'),
        $env('DB_PASSWORD'),
        [PDO::ATTR_TIMEOUT => 2, PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    if ((int) $pdo->query('SELECT 1')->fetchColumn() !== 1) {
        throw new RuntimeException('MySQL probe failed.');
    }
    $pdo = null;

    $stage = 'redis';
    $redis = new Redis();
    if (! $redis->connect($env('REDIS_HOST', '127.0.0.1'), (int) $env('REDIS_PORT', '6379'), 2.0)) {
        throw new RuntimeException('Redis connection failed.');
    }
    $redis->setOption(Redis::OPT_READ_TIMEOUT, 2.0);
    $auth = $env('REDIS_AUTH');
    if ($auth !== '' && ! $redis->auth($auth)) {
        throw new RuntimeException('Redis authentication failed.');
    }
    if (! $redis->select((int) $env('REDIS_DB', '0'))) {
        throw new RuntimeException('Redis database selection failed.');
    }
    if (! in_array($redis->ping(), [true, 'PONG', '+PONG'], true)) {
        throw new RuntimeException('Redis probe failed.');
    }
    $redis->close();
    exit(0);
} catch (Throwable) {
    // Exception messages can contain connection details; report only the stage.
    fwrite(\STDERR, sprintf("Health check failed: %s.\n", $stage));
    exit(1);
}
