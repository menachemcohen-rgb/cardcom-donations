<?php
use PHPUnit\Framework\TestCase;

final class SfClientJwtTest extends TestCase
{
    private static $priv;
    private static string $pub;

    public static function setUpBeforeClass(): void
    {
        self::$priv = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
        self::$pub = openssl_pkey_get_details(self::$priv)['key'];
    }

    private static function b64dec(string $s): string
    {
        return base64_decode(strtr($s, '-_', '+/') . str_repeat('=', (4 - strlen($s) % 4) % 4), true);
    }

    private function jwt(): string
    {
        return Org_SF_Client::build_jwt('3MVG9client', 'integration.donations@ato770.com.atosandbox',
            'https://test.salesforce.com', self::$priv, 1_800_000_000);
    }

    public function testHeaderAndClaims(): void
    {
        $parts = explode('.', $this->jwt());
        $this->assertCount(3, $parts);
        $this->assertSame(['alg' => 'RS256'], json_decode(self::b64dec($parts[0]), true));
        $this->assertSame([
            'iss' => '3MVG9client',
            'sub' => 'integration.donations@ato770.com.atosandbox',
            'aud' => 'https://test.salesforce.com',
            'exp' => 1_800_000_180,
        ], json_decode(self::b64dec($parts[1]), true));
    }

    public function testBase64UrlWithoutPadding(): void
    {
        foreach (explode('.', $this->jwt()) as $p) {
            $this->assertMatchesRegularExpression('/^[A-Za-z0-9_-]+$/', $p, 'no +, / or = padding');
        }
        $this->assertSame('-_8', Org_SF_Client::b64url("\xfb\xff"));
        $this->assertSame('YQ', Org_SF_Client::b64url('a'));
    }

    public function testSignatureVerifiesWithPublicKey(): void
    {
        [$h, $c, $s] = explode('.', $this->jwt());
        $this->assertSame(1, openssl_verify("$h.$c", self::b64dec($s), self::$pub, OPENSSL_ALGO_SHA256));
        $this->assertSame(0, openssl_verify("$h.x$c", self::b64dec($s), self::$pub, OPENSSL_ALGO_SHA256), 'tampered claims fail');
    }

    public function testAcceptsPemString(): void
    {
        openssl_pkey_export(self::$priv, $pem);
        [$h, $c, $s] = explode('.', Org_SF_Client::build_jwt('id', 'user', 'https://login.salesforce.com', $pem, 0));
        $this->assertSame(1, openssl_verify("$h.$c", self::b64dec($s), self::$pub, OPENSSL_ALGO_SHA256));
    }
}
