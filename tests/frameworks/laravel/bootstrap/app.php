<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

$app = Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        //
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );
    })->create();

if (PHP_BINARY !== '' && !preg_match('#(?:^|/)php(?:\d+(?:\.\d+)*)?$#', PHP_BINARY)) {
    $storage = dirname(PHP_BINARY) . DIRECTORY_SEPARATOR . 'storage';
    foreach (['app/public', 'app/private', 'framework/cache/data', 'framework/sessions', 'framework/views', 'logs'] as $dir) {
        $dir = $storage . DIRECTORY_SEPARATOR . $dir;
        if (!is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
    }
    $app->useStoragePath($storage);
}

return $app;
