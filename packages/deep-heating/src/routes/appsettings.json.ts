type AppSettings = {
  ENVIRONMENT: string;
  DISPLAY_ENVIRONMENT: boolean;
};

export async function get(): Promise<{ body: AppSettings }> {
  const toBool = (variable: string): boolean =>
    variable && variable.toLowerCase() === 'true';

  return {
    body: {
      ENVIRONMENT: process.env['ENVIRONMENT'] || 'development',
      DISPLAY_ENVIRONMENT: toBool(process.env['DISPLAY_ENVIRONMENT']) || false,
    },
  };
}
