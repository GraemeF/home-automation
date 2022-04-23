export type AppSettings = {
  apiUrl: string;
};

export async function get(): Promise<{ body: AppSettings }> {
  return {
    body: {
      apiUrl: process.env['API_URL'],
    },
  };
}
