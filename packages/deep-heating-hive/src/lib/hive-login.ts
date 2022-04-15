import axios, { AxiosRequestConfig } from "axios";
import {
  calculateSignature,
  getNowString,
  SRPClient,
} from "amazon-user-pool-srp-client";
import debug from "debug";

const log = debug("hive-login");

function call(action: string, body: Record<string, unknown>) {
  const request: AxiosRequestConfig = {
    url: process.env.HIVE_SSOUri,
    method: "POST",
    headers: {
      "Content-Type": "application/x-amz-json-1.1",
      "X-Amz-Target": action,
    },
    data: JSON.stringify(body),
    transformResponse: (data) => data,
  };

  return axios(request)
    .then((result) => JSON.parse(result.data))
    .catch((error) => {
      if (error.response) {
        // The request was made and the server responded with a status code
        // that falls out of the range of 2xx
        log(
          "The request was made and the server responded with a status code that falls out of the range of 2xx"
        );
        log(error.response.data);
        log(error.response.status);
        log(error.response.headers);
      } else if (error.request) {
        // The request was made but no response was received
        // `error.request` is an instance of XMLHttpRequest in the browser and an instance of
        // http.ClientRequest in node.js
        log("The request was made but no response was received", error.request);
      } else {
        // Something happened in setting up the request that triggered an Error
        log(
          "Something happened in setting up the request that triggered an Error",
          error.message
        );
      }
      log("Request:", error.config);
      const _err = JSON.parse(error.response.data);
      const err = new Error();
      err.name = _err.__type;
      err.message = _err.message;
      return Promise.reject(err);
    });
}

export async function login_srp(
  email: string,
  password: string
): Promise<{
  credentials: {
    AccessToken: string;
    ExpiresIn: number;
    IdToken: string;
    RefreshToken: string;
    TokenType: string;
  };
  username: string;
}> {
  const userPoolId = process.env.HIVE_CognitoUserPoolUsers?.split("_")[1];
  const srp = new SRPClient(userPoolId);
  const SRP_A = srp.calculateA();
  const { ChallengeName, ChallengeParameters, Session } = await call(
    "AWSCognitoIdentityProviderService.InitiateAuth",
    {
      ClientId: process.env.HIVE_CognitoUserPoolClientWeb,
      AuthFlow: "USER_SRP_AUTH",
      AuthParameters: {
        USERNAME: email,
        SRP_A,
      },
    }
  );
  const hkdf = srp.getPasswordAuthenticationKey(
    ChallengeParameters.USER_ID_FOR_SRP,
    password,
    ChallengeParameters.SRP_B,
    ChallengeParameters.SALT
  );
  const dateNow = getNowString();
  const signatureString = calculateSignature(
    hkdf,
    userPoolId,
    ChallengeParameters.USER_ID_FOR_SRP,
    ChallengeParameters.SECRET_BLOCK,
    dateNow
  );
  const { AuthenticationResult } = await call(
    "AWSCognitoIdentityProviderService.RespondToAuthChallenge",
    {
      ClientId: process.env.HIVE_CognitoUserPoolClientWeb,
      ChallengeName,
      ChallengeResponses: {
        PASSWORD_CLAIM_SIGNATURE: signatureString,
        PASSWORD_CLAIM_SECRET_BLOCK: ChallengeParameters.SECRET_BLOCK,
        TIMESTAMP: dateNow,
        USERNAME: ChallengeParameters.USER_ID_FOR_SRP,
      },
      Session,
    }
  );
  return {
    username: ChallengeParameters.USERNAME,
    credentials: AuthenticationResult,
  };
}

/* Additional calls as part of standalone user pool client */

export function refreshCredentials(refreshToken: string) {
  return call("AWSCognitoIdentityProviderService.InitiateAuth", {
    ClientId: process.env.HIVE_CognitoUserPoolClientWeb,
    AuthFlow: "REFRESH_TOKEN_AUTH",
    AuthParameters: {
      REFRESH_TOKEN: refreshToken,
    },
  }).then(({ AuthenticationResult }) => ({
    ...AuthenticationResult,
    RefreshToken: AuthenticationResult.RefreshToken || refreshToken,
  }));
}

export function resendConfirmationCode(Username: string) {
  return call("AWSCognitoIdentityProviderService.ResendConfirmationCode", {
    ClientId: process.env.HIVE_CognitoUserPoolClientWeb,
    Username,
  });
}
