# Configuration

`aws_config.dart` holds placeholders. To run this app against your own
backend, replace them with values from your AWS deployment:

| Constant | Where to find it |
|---|---|
| `userPoolId` | Cognito → User pools → your pool → Pool ID |
| `clientId` | Cognito → your pool → App integration → App client ID |
| `apiBaseUrl` | API Gateway → your API → Stages → `prod` → Invoke URL |

The app client is configured without a client secret, which is the
correct pattern for a public mobile client — a secret embedded in a
distributed binary provides no security.
