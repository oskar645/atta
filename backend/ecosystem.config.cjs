module.exports = {
  apps: [
    {
      name: 'atta-backend',
      cwd: __dirname,
      script: 'dist/main.js',
      interpreter: 'node',
      node_args: '-r dotenv/config',
      env: {
        NODE_ENV: 'production',
        DOTENV_CONFIG_PATH: '.env',
      },
      env_production: {
        NODE_ENV: 'production',
        DOTENV_CONFIG_PATH: '.env',
      },
      autorestart: true,
      max_memory_restart: '500M',
      out_file: 'logs/pm2-out.log',
      error_file: 'logs/pm2-error.log',
      time: true,
    },
  ],
};
