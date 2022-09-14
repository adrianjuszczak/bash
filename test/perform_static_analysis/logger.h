#ifndef LOGGER_H
#define LOGGER_H

#include "ianalysis.h"

class Logger final : public IAnalysis
{
public:
    Logger(const std::string &ctxId, const std::string &description); // FIX ME: def param
    ~Logger() override;
    virtual void log(const std::string &ctxId, const std::string &msg) override;
private:
    std::string m_contextId;
    std::string m_description;
};


#endif