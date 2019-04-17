//
//  SKNetworking.h
//  SKNetworking_Example
//
//  Created by 李烁凯 on 2019/4/9.
//  Copyright © 2019 luckyLSK. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define SK_REQUEST_TIMEOUT 10.f

#define SK_ERROR_IMFORMATION @"网络出现错误，请检查网络连接"

#define SK_ERROR [NSError errorWithDomain:@"com.ediancha.SKNetworking.ErrorDomain" code:-999 userInfo:@{ NSLocalizedDescriptionKey:SK_ERROR_IMFORMATION}]

#define DIRECTORYPATH [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/"] stringByAppendingString:@"/SKNetWorking/"];

#define MAX_CACHE_SIZE (10 * 1024 * 1024)

@interface SKNetworking : NSObject

/**
 *  网络状态
 */
typedef NS_ENUM(NSInteger, SKNetworkStatus) {
    /**
     *  未知网络
     */
    SKNetworkStatusUnknown             = 1 << 0,
    /**
     *  无法连接
     */
    SKNetworkStatusNotReachable        = 1 << 2,
    /**
     *  网络正常
     */
    SKNetworkStatusNormal              = 1 << 3
};

/**
 *  请求方式
 */
typedef NS_ENUM(NSInteger, SKRequestType) {
    /**
     *  POST方式来进行请求
     */
    SKPOSTRequest = 1 << 0,
    /**
     *  GET方式来进行请求
     */
    SKGETRequest  = 1 << 1
};

/**
 *  数据串行方式
 */
typedef NS_ENUM(NSInteger, SKSerializerType) {
    /**
     *  HTTP方式来进行请求或响应
     */
    SKHTTPSerializer = 1 << 0,
    /**
     *  JSON方式来进行请求或响应
     */
    SKJSONSerializer = 1 << 1
};

/**
 *  请求任务
 */
typedef NSURLSessionTask SKURLSessionTask;

/**
 *  成功回调
 *
 *  @param response 成功后返回的数据
 */
typedef void(^SKResponseSuccessBlock)(id response);

/**
 *  失败回调
 *
 *  @param error 失败后返回的错误信息
 */
typedef void(^SKResponseFailBlock)(NSError *error, BOOL isNetworking);

/**
 *  进度
 *
 *  @param bytesRead              已下载或者上传进度的大小
 *  @param totalBytes                总下载或者上传进度的大小
 */
typedef void(^SKNetWorkingProgress)(int64_t bytesRead,
                                    int64_t totalBytes);

/**
 *  配置请求头
 *
 *  @param httpHeaders 请求头参数
 */
+ (void)configHttpHeaders:(NSDictionary *)httpHeaders;

/**
 *  取消所有请求
 */
+ (void)cancelAllRequest;

/**
 *  根据url取消请求
 *
 *  @param url 请求url
 */
+ (void)cancelRequestWithURL:(NSString *)url;

/**
 *    获取缓存总大小
 *
 *    @return 缓存大小
 */
+ (unsigned long long)totalCacheSize;

/**
 *    清除缓存
 */
+ (void)clearCaches;

/**
 *    设置超时时间
 *
 *  @param timeout 超时时间
 */
+ (void)setupTimeout:(NSTimeInterval)timeout;

/**
 *  更新请求或者返回数据的解析方式(0为HTTP模式，1为JSON模式)
 *
 *  @param requestType  请求数据解析方式
 *  @param responseType 返回数据解析方式
 */
+ (void)updateRequestSerializerType:(SKSerializerType)requestType
                 responseSerializer:(SKSerializerType)responseType;

/**
 *  统一请求接口
 *
 *  @param url              请求路径
 *  @param params           拼接参数
 *  @param httpMethod       请求方式（0为POST,1为GET）
 *  @param useCache         是否使用缓存
 *  @param progressBlock    进度回调
 *  @param successBlock     成功回调block
 *  @param failBlock        失败回调block
 *
 *  @return 返回的对象中可取消请求
 */
+ (SKURLSessionTask *)requestWithUrl:(NSString *)url
                              params:(NSDictionary *)params
                            useCache:(BOOL)useCache
                         httpMedthod:(SKRequestType)httpMethod
                       progressBlock:(SKNetWorkingProgress)progressBlock
                        successBlock:(SKResponseSuccessBlock)successBlock
                           failBlock:(SKResponseFailBlock)failBlock;

/**
 *  图片上传接口
 *
 *    @param imageArr            图片对象
 *  @param url              请求路径
 *    @param name             图片名
 *    @param type             默认为image/jpeg
 *    @param params           拼接参数
 *    @param progressBlock    上传进度
 *    @param successBlock     成功回调
 *    @param failBlock        失败回调
 *
 *  @return 返回的对象中可取消请求
 */
+ (SKURLSessionTask *)uploadWithImageArr:(NSArray *)imageArr
                                     url:(NSString *)url
                                    name:(NSString *)name
                                    type:(NSString *)type
                                  params:(NSDictionary *)params
                           progressBlock:(SKNetWorkingProgress)progressBlock
                            successBlock:(SKResponseSuccessBlock)successBlock
                               failBlock:(SKResponseFailBlock)failBlock;

/**
 *  文件上传接口
 *
 *  @param url              上传文件接口地址
 *  @param file    上传文件路径
 *  @param progressBlock    上传进度
 *    @param successBlock     成功回调
 *    @param failBlock        失败回调
 *
 *  @return 返回的对象中可取消请求
 */
+ (SKURLSessionTask *)uploadFileWithUrl:(NSString *)url
                                   file:(NSString *)file
                                   type:(NSString *)type
                                   name:(NSString *)name
                                 params:(NSDictionary *)params
                          progressBlock:(SKNetWorkingProgress)progressBlock
                           successBlock:(SKResponseSuccessBlock)successBlock
                              failBlock:(SKResponseFailBlock)failBlock;

/**
 *  文件下载接口
 *
 *  @param url           下载文件接口地址
 *  @param saveToPath    存储目录
 *  @param progressBlock 下载进度
 *  @param successBlock  成功回调
 *  @param failBlock     下载回调
 *
 *  @return 返回的对象可取消请求
 */
+ (SKURLSessionTask *)downloadWithUrl:(NSString *)url
                           saveToPath:(NSURL *)saveToPath
                        progressBlock:(SKNetWorkingProgress)progressBlock
                         successBlock:(SKResponseSuccessBlock)successBlock
                            failBlock:(SKResponseFailBlock)failBlock;

@end


