#include "logger.h"
#include <iostream>

Logger::Logger(const std::string &ctxId, const std::string &description = "")
: m_contextId{ctxId}
, m_description{description}
{
}

Logger::~Logger() 
{
    std::cout << "Logger is being destructed! \n";
}

void Logger::log(const std::string &ctxId, const std::string &msg)
{
    std::cout << "Context ID: "  << ctxId << std::endl
              << "Description: " << msg   << std::endl;
}

void Logger::foo(const std::string &msg) 
{
    std::cout << "foo \n";
}