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

namespace App\Listener;

use Hyperf\Contract\ConfigInterface;
use Hyperf\Di\Annotation\AnnotationCollector;
use Hyperf\Di\Annotation\MultipleAnnotation;
use Hyperf\Event\Annotation\Listener;
use Hyperf\Event\Contract\ListenerInterface;
use Hyperf\Framework\Event\BootApplication;
use Hyperf\HttpServer\Annotation\Middleware;
use Hyperf\HttpServer\Router\DispatcherFactory;
use Hyperf\Swagger\Annotation as SA;
use Hyperf\Swagger\Util;
use OpenApi\Annotations\Operation;

#[Listener]
final class RegisterSwaggerRoutesListener implements ListenerInterface
{
    public function __construct(
        private readonly ConfigInterface $config,
        private readonly DispatcherFactory $factory
    ) {}

    public function listen(): array
    {
        return [BootApplication::class];
    }

    public function process(object $event): void
    {
        // Hyperf's listener registers these routes only while Swagger UI is enabled.
        if ($this->config->get('swagger.enable', false)) {
            return;
        }

        $annotations = [SA\Get::class, SA\Head::class, SA\Patch::class, SA\Post::class,
            SA\Put::class, SA\Delete::class, SA\Options::class];

        foreach ($annotations as $annotationClass) {
            foreach (AnnotationCollector::getMethodsByAnnotation($annotationClass) as $item) {
                $class = $item['class'];
                $method = $item['method'];
                /** @var MultipleAnnotation $annotation */
                $annotation = $item['annotation'];
                $classAnnotations = AnnotationCollector::getClassAnnotations($class);
                $methodAnnotations = AnnotationCollector::getClassMethodAnnotation($class, $method);
                /** @var SA\HyperfServer[] $servers */
                $servers = Util::findAnnotations($methodAnnotations, SA\HyperfServer::class)
                    ?: Util::findAnnotations($classAnnotations, SA\HyperfServer::class);
                /** @var Middleware[] $middlewareAnnotations */
                $middlewareAnnotations = array_merge(
                    Util::findAnnotations($methodAnnotations, Middleware::class),
                    Util::findAnnotations($classAnnotations, Middleware::class)
                );
                $middlewares = array_map(static fn (Middleware $middleware) => $middleware->priorityMiddleware, $middlewareAnnotations);

                /** @var Operation $operation */
                foreach ($annotation->toAnnotations() as $operation) {
                    foreach ($servers as $server) {
                        $this->factory->getRouter($server->name)->addRoute(
                            [$operation->method],
                            $operation->path,
                            [$class, $method],
                            ['middleware' => $middlewares]
                        );
                    }
                }
            }
        }
    }
}
