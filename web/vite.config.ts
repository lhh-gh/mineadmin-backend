import path from 'node:path'
import process from 'node:process'
import dayjs from 'dayjs'
import { defineConfig, loadEnv } from 'vite'
import pkg from './package.json' with { type: 'json' }
import createVitePlugins from './vite/index.ts'
import { exclude, include } from './vite/optimize.ts'

// https://cn.vite.dev/config/
export default async ({ mode, command }) => {
  const env = loadEnv(mode, process.cwd())
  function isProduction(): boolean {
    return mode === 'production'
  }

  // 全局 scss 资源
  // const scssFiles: string[] = []
  // fs.readdirSync('src/assets/styles/resources').forEach((dirname) => {
  //   if (fs.statSync(`src/assets/styles/resources/${dirname}`).isFile()) {
  //     scssFiles.push(`@use "src/assets/styles/resources/${dirname}" as *;`)
  //   }
  // })

  const proxyPrefix = env.VITE_PROXY_PREFIX
  return defineConfig({
    base: env.VITE_APP_ROOT_BASE,
    // 开发服务器选项 https://cn.vite.dev/config/#server-options
    server: {
      open: true,
      port: Number(env.VITE_APP_PORT ?? process.env.port),
      proxy: {
        [proxyPrefix]: {
          target: env.VITE_APP_API_BASEURL,
          changeOrigin: command === 'serve' && env.VITE_OPEN_PROXY === 'true',
          rewrite: path => path.replace(new RegExp(`^${proxyPrefix}`), ''),
        },
      },
    },
    // 构建选项 https://cn.vite.dev/config/#server-fsserve-root
    build: {
      outDir: isProduction ? 'dist' : `dist-${mode}`,
      sourcemap: env.VITE_BUILD_SOURCEMAP === 'true',
      minify: 'oxc',
      cssMinify: 'esbuild',
      rolldownOptions: {
        output: {
          minify: {
            compress: {
              dropConsole: isProduction(),
              dropDebugger: isProduction(),
            },
          },
          codeSplitting: true,
          chunkFileNames: 'static/js/[name]-[hash].js',
          entryFileNames: 'static/js/[name]-[hash].js',
          assetFileNames: 'static/[ext]/[name]-[hash].[ext]',
          manualChunks: {
            echarts: ['echarts'], // 将 echarts 单独打包
          },
        },
      },
    },
    define: {
      __MINE_SYSTEM_INFO__: JSON.stringify({
        pkg: {
          version: pkg.version,
          dependencies: pkg.dependencies,
          devDependencies: pkg.devDependencies,
        },
        lastBuildTime: dayjs().format('YYYY-MM-DD HH:mm:ss'),
      }),
    },
    plugins: createVitePlugins(env, command === 'build'),
    resolve: {
      alias: {
        '@': path.resolve(import.meta.dirname, 'src'),
        '#': path.resolve(import.meta.dirname, 'types'),
        '$': path.resolve(import.meta.dirname, 'src/plugins'),
        '~': path.resolve(import.meta.dirname, 'src/modules'),
      },
    },
    css: {
      preprocessorOptions: {
        scss: {
          api: 'modern-compiler',
          // additionalData: scssFiles.join(''),
          javascriptEnabled: true,
        },
      },
    },
    optimizeDeps: { include, exclude },
  })
}
