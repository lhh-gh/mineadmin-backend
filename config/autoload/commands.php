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
use Hyperf\Database\Commands\Migrations\InstallCommand;
use Hyperf\Database\Commands\Migrations\MigrateCommand;
use Hyperf\Database\Commands\Seeders\SeedCommand;

// Keep database initialization available when devtool is excluded from the image.
return [
    InstallCommand::class,
    MigrateCommand::class,
    SeedCommand::class,
];
