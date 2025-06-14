using System.Net;
using System.Net.Http.Headers;
using N_m3u8DL_RE.Common.Log;
using N_m3u8DL_RE.Common.Resource;

namespace N_m3u8DL_RE.Common.Util;

/// <summary>
/// 表示不应重试的HTTP异常（如401、403、404等状态码）
/// </summary>
public class NonRetryableHttpException : Exception
{
    public HttpStatusCode StatusCode { get; }
    
    public NonRetryableHttpException(HttpStatusCode statusCode, string message) : base(message)
    {
        StatusCode = statusCode;
    }
    
    public NonRetryableHttpException(HttpStatusCode statusCode, string message, Exception innerException) : base(message, innerException)
    {
        StatusCode = statusCode;
    }
}

public static class HTTPUtil
{
    public static readonly HttpClientHandler HttpClientHandler = new()
    {
        AllowAutoRedirect = false,
        AutomaticDecompression = DecompressionMethods.All,
        ServerCertificateCustomValidationCallback = (sender, cert, chain, sslPolicyErrors) => true,
        MaxConnectionsPerServer = 1024,
    };

    public static readonly HttpClient AppHttpClient = new(HttpClientHandler)
    {
        Timeout = TimeSpan.FromSeconds(100),
        DefaultRequestVersion = HttpVersion.Version20,
        DefaultVersionPolicy = HttpVersionPolicy.RequestVersionOrHigher,
    };

    private static async Task<HttpResponseMessage> DoGetAsync(string url, Dictionary<string, string>? headers = null)
    {
        Logger.Debug(ResString.fetch + url); 
        using var webRequest = new HttpRequestMessage(HttpMethod.Get, url);
        webRequest.Headers.TryAddWithoutValidation("Accept-Encoding", "gzip, deflate");
        webRequest.Headers.CacheControl = CacheControlHeaderValue.Parse("no-cache");
        webRequest.Headers.Connection.Clear();
        if (headers != null)
        {
            foreach (var item in headers)
            {
                webRequest.Headers.TryAddWithoutValidation(item.Key, item.Value);
            }
        }
        Logger.Debug(webRequest.Headers.ToString());
        // 手动处理跳转，以免自定义Headers丢失
        var webResponse = await AppHttpClient.SendAsync(webRequest, HttpCompletionOption.ResponseHeadersRead);
        if (((int)webResponse.StatusCode).ToString().StartsWith("30"))
        {
            HttpResponseHeaders respHeaders = webResponse.Headers;
            Logger.Debug(respHeaders.ToString());
            if (respHeaders.Location != null)
            {
                var redirectedUrl = "";
                if (!respHeaders.Location.IsAbsoluteUri)
                {
                    Uri uri1 = new Uri(url);
                    Uri uri2 = new Uri(uri1, respHeaders.Location);
                    redirectedUrl = uri2.ToString();
                }
                else
                {
                    redirectedUrl = respHeaders.Location.AbsoluteUri;
                }
                    
                if (redirectedUrl != url)
                {
                    Logger.Extra($"Redirected => {redirectedUrl}");
                    return await DoGetAsync(redirectedUrl, headers);
                }
            }
        }
        // 手动将跳转后的URL设置进去, 用于后续取用
        webResponse.Headers.Location = new Uri(url);
        
        // 检查是否为不可重试的状态码
        if (IsNonRetryableStatusCode(webResponse.StatusCode))
        {
            Logger.ErrorMarkUp($"[red]HTTP {(int)webResponse.StatusCode} {webResponse.StatusCode}: 请求失败，不进行重试[/]");
            throw new NonRetryableHttpException(webResponse.StatusCode,
                $"HTTP {(int)webResponse.StatusCode} {webResponse.StatusCode}: Request failed with non-retryable status code");
        }
        
        webResponse.EnsureSuccessStatusCode();
        return webResponse;
    }

    public static async Task<byte[]> GetBytesAsync(string url, Dictionary<string, string>? headers = null)
    {
        if (url.StartsWith("file:"))
        {
            return await File.ReadAllBytesAsync(new Uri(url).LocalPath);
        }
        var webResponse = await DoGetAsync(url, headers);
        var bytes = await webResponse.Content.ReadAsByteArrayAsync();
        Logger.Debug(HexUtil.BytesToHex(bytes, " "));
        return bytes;
    }

    /// <summary>
    /// 获取网页源码
    /// </summary>
    /// <param name="url"></param>
    /// <param name="headers"></param>
    /// <returns></returns>
    public static async Task<string> GetWebSourceAsync(string url, Dictionary<string, string>? headers = null)
    {
        var webResponse = await DoGetAsync(url, headers);
        string htmlCode = await webResponse.Content.ReadAsStringAsync();
        Logger.Debug(htmlCode);
        return htmlCode;
    }

    private static bool CheckMPEG2TS(HttpResponseMessage? webResponse)
    {
        var mediaType = webResponse?.Content.Headers.ContentType?.MediaType?.ToLower();
        return mediaType is "video/ts" or "video/mp2t" or "video/mpeg";
    }

    /// <summary>
    /// 获取网页源码和跳转后的URL
    /// </summary>
    /// <param name="url"></param>
    /// <param name="headers"></param>
    /// <returns>(Source Code, RedirectedUrl)</returns>
    public static async Task<(string, string)> GetWebSourceAndNewUrlAsync(string url, Dictionary<string, string>? headers = null)
    {
        string htmlCode;
        var webResponse = await DoGetAsync(url, headers);
        if (CheckMPEG2TS(webResponse))
        {
            htmlCode = ResString.ReLiveTs;
        }
        else
        {
            htmlCode = await webResponse.Content.ReadAsStringAsync();
        }
        Logger.Debug(htmlCode);
        return (htmlCode, webResponse.Headers.Location != null ? webResponse.Headers.Location.AbsoluteUri : url);
    }

    public static async Task<string> GetPostResponseAsync(string Url, byte[] postData)
    {
        string htmlCode;
        using HttpRequestMessage request = new(HttpMethod.Post, Url);
        request.Headers.TryAddWithoutValidation("Content-Type", "application/json");
        request.Headers.TryAddWithoutValidation("Content-Length", postData.Length.ToString());
        request.Content = new ByteArrayContent(postData);
        var webResponse = await AppHttpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
        htmlCode = await webResponse.Content.ReadAsStringAsync();
        return htmlCode;
    }

    /// <summary>
    /// 检查是否为不可重试的HTTP状态码
    /// </summary>
    /// <param name="statusCode">HTTP状态码</param>
    /// <returns>如果不可重试返回true，否则返回false</returns>
    private static bool IsNonRetryableStatusCode(HttpStatusCode statusCode)
    {
        return statusCode switch
        {
            HttpStatusCode.Unauthorized => true,        // 401
            HttpStatusCode.Forbidden => true,           // 403
            HttpStatusCode.NotFound => true,            // 404
            HttpStatusCode.TooManyRequests => true,     // 429
            HttpStatusCode.InternalServerError => true, // 500
            HttpStatusCode.BadGateway => true,          // 502
            HttpStatusCode.ServiceUnavailable => true,  // 503
            _ => false
        };
    }
}